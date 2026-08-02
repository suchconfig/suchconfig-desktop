use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use parking_lot::Mutex;
use serde::Serialize;
use std::collections::HashMap;
use std::net::{IpAddr, Ipv4Addr, SocketAddr, UdpSocket};
use std::sync::Arc;
use std::time::{Duration, SystemTime, UNIX_EPOCH};
use tauri::{AppHandle, Emitter};
use thiserror::Error;

use super::device::DeviceIdentity;
use super::protocol::SERVICE_TYPE;
use super::store::PeerStore;

const OFFLINE_AFTER_SECS: u64 = 300;
const RESOLVED_MAX_AGE_SECS: u64 = 180;
const FOUND_ONLINE_SECS: u64 = 90;
const HANDOFF_PORT_STABLE_SAMPLES: u32 = 2;
const IROH_MDNS_PRESENCE_PORT: u16 = 9;

#[derive(Debug, Error)]
pub enum DiscoveryError {
    #[error("mdns error: {0}")]
    Mdns(String),
    #[error("{0}")]
    Message(String),
}

#[derive(Debug, Clone, Serialize, PartialEq)]
#[serde(rename_all = "camelCase")]
pub struct LanPeerStatus {
    pub device_id: String,
    pub device_name: String,
    pub online: bool,
    pub handoff_ready: bool,
    pub host: Option<String>,
    pub port: Option<u16>,
    pub last_seen: Option<u64>,
    pub pinned: bool,
}

#[derive(Debug, Clone)]
struct SeenPeer {
    host: String,
    port: u16,
    last_found: u64,
    last_resolved: u64,
    stable_samples: u32,
    presence_only: bool,
    iroh_dial_addrs: Vec<SocketAddr>,
}

#[derive(Debug, Clone)]
struct ParsedResolved {
    device_id: String,
    port: u16,
    host: String,
    presence_only: bool,
    iroh_dial_addrs: Vec<SocketAddr>,
}

struct DiscoveryInner {
    daemon: Option<ServiceDaemon>,
    browse_receiver: Option<mdns_sd::Receiver<ServiceEvent>>,
    seen: HashMap<String, SeenPeer>,
    rejected_handoff_ports: HashMap<String, std::collections::HashSet<u16>>,
    listen_port: u16,
    local_device_id: String,
    registered_hostname: String,
    registered_device_name: String,
    local_iroh_dial_addrs: Vec<SocketAddr>,
    running: bool,
    last_emitted_peers: Vec<LanPeerStatus>,
}

pub struct DiscoveryManager {
    inner: Arc<Mutex<DiscoveryInner>>,
}

impl Default for DiscoveryManager {
    fn default() -> Self {
        Self {
            inner: Arc::new(Mutex::new(DiscoveryInner {
                daemon: None,
                browse_receiver: None,
                seen: HashMap::new(),
                rejected_handoff_ports: HashMap::new(),
                listen_port: 0,
                local_device_id: String::new(),
                registered_hostname: String::new(),
                registered_device_name: String::new(),
                local_iroh_dial_addrs: Vec::new(),
                running: false,
                last_emitted_peers: Vec::new(),
            })),
        }
    }
}

impl Clone for DiscoveryManager {
    fn clone(&self) -> Self {
        Self {
            inner: Arc::clone(&self.inner),
        }
    }
}

impl DiscoveryManager {
    pub fn start(
        &self,
        app: &AppHandle,
        listen_port: u16,
        iroh_dial_addrs: &[SocketAddr],
    ) -> Result<(), DiscoveryError> {
        {
            let inner = self.inner.lock();
            if inner.running
                && inner.listen_port == listen_port
                && inner.local_iroh_dial_addrs.as_slice() == iroh_dial_addrs
            {
                return Ok(());
            }
        }

        if self.inner.lock().running {
            return self.reregister_listen_port(app, listen_port, iroh_dial_addrs);
        }

        let mut inner = self.inner.lock();

        let daemon = ServiceDaemon::new().map_err(|e| DiscoveryError::Mdns(e.to_string()))?;
        let identity = DeviceIdentity::load_or_create(app)
            .map_err(|e| DiscoveryError::Message(e.to_string()))?;

        let hostname = mdns_registration_hostname(&identity.record.device_id);
        let seed_ipv4 = guess_local_lan_ipv4()
            .map(|ip| ip.to_string())
            .unwrap_or_default();
        if !seed_ipv4.is_empty() {
            eprintln!("[suchconfig-p2p] mDNS seed IPv4 {seed_ipv4} for LAN advertisement");
        }

        let advertised_port = register_suchconfig_service(
            &daemon,
            &identity,
            listen_port,
            seed_ipv4.as_str(),
            iroh_dial_addrs,
        )?;
        if listen_port == 0 {
            eprintln!(
                "[suchconfig-p2p] mDNS advertising iroh presence for {} (presence port {advertised_port})",
                identity.record.device_id
            );
        } else {
            eprintln!(
                "[suchconfig-p2p] mDNS advertising {} on port {listen_port}",
                identity.record.device_id
            );
        }

        let receiver = daemon
            .browse(SERVICE_TYPE)
            .map_err(|e| DiscoveryError::Mdns(e.to_string()))?;

        inner.daemon = Some(daemon);
        inner.browse_receiver = Some(receiver);
        inner.listen_port = listen_port;
        inner.local_device_id = identity.record.device_id.clone();
        inner.registered_hostname = hostname.clone();
        inner.registered_device_name = identity.record.device_name.clone();
        inner.local_iroh_dial_addrs = iroh_dial_addrs.to_vec();
        inner.running = true;
        inner.seen.clear();
        inner.last_emitted_peers.clear();

        let app_handle = app.clone();
        let manager = self.clone();
        std::thread::spawn(move || discovery_poll_loop(app_handle, manager));

        Ok(())
    }

    fn reregister_listen_port(
        &self,
        app: &AppHandle,
        listen_port: u16,
        iroh_dial_addrs: &[SocketAddr],
    ) -> Result<(), DiscoveryError> {
        let mut inner = self.inner.lock();
        let Some(daemon) = inner.daemon.as_ref() else {
            drop(inner);
            return self.start(app, listen_port, iroh_dial_addrs);
        };

        let old_port = inner.listen_port;
        let device_id = inner.local_device_id.clone();
        let fullname = format!("{device_id}.{SERVICE_TYPE}");

        if let Ok(rx) = daemon.unregister(&fullname) {
            let _ = rx.recv_timeout(Duration::from_millis(500));
        }
        eprintln!(
            "[suchconfig-p2p] mDNS re-register {device_id} port {old_port} -> {listen_port}"
        );

        let identity = DeviceIdentity::load_or_create(app)
            .map_err(|e| DiscoveryError::Message(e.to_string()))?;
        let hostname = mdns_registration_hostname(&identity.record.device_id);
        let seed_ipv4 = guess_local_lan_ipv4()
            .map(|ip| ip.to_string())
            .unwrap_or_default();
        let advertised_port = register_suchconfig_service(
            daemon,
            &identity,
            listen_port,
            seed_ipv4.as_str(),
            iroh_dial_addrs,
        )?;

        inner.listen_port = listen_port;
        inner.registered_hostname = hostname;
        inner.registered_device_name = identity.record.device_name.clone();
        inner.local_iroh_dial_addrs = iroh_dial_addrs.to_vec();
        if listen_port == 0 {
            eprintln!(
                "[suchconfig-p2p] mDNS re-register iroh presence for {} addrs={iroh_dial_addrs:?} (presence port {advertised_port})",
                identity.record.device_id
            );
        } else {
            eprintln!(
                "[suchconfig-p2p] mDNS advertising {} on port {listen_port}",
                identity.record.device_id
            );
        }
        Ok(())
    }

    pub fn stop(&self) {
        let mut inner = self.inner.lock();
        inner.running = false;
        let service_fullname = if inner.local_device_id.is_empty() {
            None
        } else {
            Some(format!("{}.{}", inner.local_device_id, SERVICE_TYPE))
        };
        if let Some(daemon) = inner.daemon.take() {
            if let Some(ref fullname) = service_fullname {
                if let Ok(rx) = daemon.unregister(fullname) {
                    let _ = rx.recv_timeout(Duration::from_millis(500));
                }
                eprintln!("[suchconfig-p2p] mDNS unregistered {fullname}");
            }
            if let Ok(rx) = daemon.shutdown() {
                let _ = rx.recv_timeout(Duration::from_millis(500));
            }
        }
        inner.browse_receiver = None;
        inner.seen.clear();
        inner.rejected_handoff_ports.clear();
        inner.registered_hostname.clear();
        inner.registered_device_name.clear();
        inner.local_iroh_dial_addrs.clear();
        inner.last_emitted_peers.clear();
    }

    pub fn drain_browse_events(&self) {
        let mut events = Vec::new();
        {
            let inner = self.inner.lock();
            if let Some(receiver) = inner.browse_receiver.as_ref() {
                while let Ok(event) = receiver.try_recv() {
                    events.push(event);
                }
            }
        }
        for event in events {
            self.ingest_event(event);
        }
    }

    pub fn ingest_event(&self, event: ServiceEvent) {
        let mut inner = self.inner.lock();
        match event {
            ServiceEvent::ServiceResolved(info) => {
                let Some(parsed) = parse_resolved_service(&info) else {
                    return;
                };
                let device_id = parsed.device_id;
                if device_id == inner.local_device_id {
                    return;
                }
                let now = now_secs();
                let srv_port = info.get_port();
                let port = parsed.port;
                let host = parsed.host;
                let port_changed = inner
                    .seen
                    .get(&device_id)
                    .map(|prev| prev.port != port)
                    .unwrap_or(false);
                if port_changed {
                    inner.rejected_handoff_ports.remove(&device_id);
                    if let Some(prev) = inner.seen.get(&device_id) {
                        eprintln!(
                            "[suchconfig-p2p] peer {device_id} endpoint port {} -> {port} ({host})",
                            prev.port
                        );
                    } else {
                        eprintln!(
                            "[suchconfig-p2p] peer {device_id} endpoint resolved {host}:{port} (srv {srv_port})"
                        );
                    }
                } else if !host.is_empty() {
                    if let Some(prev) = inner.seen.get(&device_id) {
                        if prev.host.is_empty() {
                            eprintln!(
                                "[suchconfig-p2p] peer {device_id} endpoint address resolved {host}:{port}"
                            );
                        }
                    }
                }
                let entry = inner.seen.entry(device_id.clone()).or_insert(SeenPeer {
                    host: String::new(),
                    port: 0,
                    last_found: now,
                    last_resolved: 0,
                    stable_samples: 0,
                    presence_only: false,
                    iroh_dial_addrs: Vec::new(),
                });
                entry.presence_only = parsed.presence_only;
                if !parsed.iroh_dial_addrs.is_empty() {
                    if entry.iroh_dial_addrs != parsed.iroh_dial_addrs {
                        eprintln!(
                            "[suchconfig-p2p] peer {device_id} iroh dial addrs from mDNS: {:?}",
                            parsed.iroh_dial_addrs
                        );
                    }
                    entry.iroh_dial_addrs = parsed.iroh_dial_addrs;
                }
                let prev_endpoint = if is_ipv4_literal(&entry.host) && entry.port > 0 {
                    Some((entry.host.clone(), entry.port))
                } else {
                    None
                };
                entry.port = port;
                entry.last_found = now;
                entry.last_resolved = now;
                if is_ipv4_literal(&host) {
                    entry.host = host;
                } else if !entry.host.is_empty() && !is_ipv4_literal(&entry.host) {
                    entry.host.clear();
                }
                if port_changed {
                    entry.stable_samples = 0;
                }
                let new_endpoint = if is_ipv4_literal(&entry.host) && entry.port > 0 {
                    Some((entry.host.clone(), entry.port))
                } else {
                    None
                };
                entry.stable_samples = match (prev_endpoint, new_endpoint) {
                    (Some(prev), Some(new)) if prev == new => {
                        (entry.stable_samples + 1).min(HANDOFF_PORT_STABLE_SAMPLES)
                    }
                    (_, Some(_)) => 1,
                    _ => 0,
                };
            }
            ServiceEvent::ServiceFound(_, fullname) => {
                let instance = instance_id_from_fullname(&fullname);
                if instance.is_empty() || instance == inner.local_device_id {
                    return;
                }
                let now = now_secs();
                let entry = inner.seen.entry(instance).or_insert(SeenPeer {
                    host: String::new(),
                    port: 0,
                    last_found: now,
                    last_resolved: 0,
                    stable_samples: 0,
                    presence_only: false,
                    iroh_dial_addrs: Vec::new(),
                });
                entry.last_found = now;
            }
            ServiceEvent::ServiceRemoved(_, fullname) => {
                let instance = instance_id_from_fullname(&fullname);
                if instance.is_empty() || instance == inner.local_device_id {
                    return;
                }
                if inner.seen.remove(&instance).is_some() {
                    eprintln!("[suchconfig-p2p] peer {instance} mDNS service removed");
                }
            }
            _ => {}
        }
    }

    fn peer_is_online(seen: &SeenPeer, now: u64) -> bool {
        if now.saturating_sub(seen.last_found) <= FOUND_ONLINE_SECS {
            return true;
        }
        seen.port > 0
            && seen.last_resolved > 0
            && now.saturating_sub(seen.last_resolved) <= OFFLINE_AFTER_SECS
    }

    fn handoff_ready(seen: &SeenPeer, now: u64, port_rejected: bool) -> bool {
        if seen.presence_only {
            return Self::peer_is_online(seen, now);
        }
        !port_rejected
            && seen.stable_samples >= HANDOFF_PORT_STABLE_SAMPLES
            && Self::peer_is_online(seen, now)
            && is_ipv4_literal(&seen.host)
            && seen.port > 0
            && seen.last_resolved > 0
            && now.saturating_sub(seen.last_resolved) <= RESOLVED_MAX_AGE_SECS
    }

    pub fn peer_statuses(&self, app: &AppHandle) -> Result<Vec<LanPeerStatus>, DiscoveryError> {
        let pinned = PeerStore::list(app).map_err(|e| DiscoveryError::Message(e.to_string()))?;
        let inner = self.inner.lock();
        let seen = inner.seen.clone();
        let rejected_ports = inner.rejected_handoff_ports.clone();
        drop(inner);
        let now = now_secs();

        let mut out: Vec<LanPeerStatus> = pinned
            .into_iter()
            .map(|peer| {
                let seen_entry = seen.get(&peer.device_id);
                let (online, handoff_ready, host, port, last_seen) = match seen_entry {
                    Some(s) => {
                        let online = Self::peer_is_online(s, now);
                        let port_rejected = rejected_ports
                            .get(&peer.device_id)
                            .map(|ports| ports.contains(&s.port))
                            .unwrap_or(false);
                        (
                            online,
                            Self::handoff_ready(s, now, port_rejected),
                            Some(s.host.clone()),
                            Some(s.port),
                            Some(s.last_resolved),
                        )
                    }
                    None => (false, false, None, None, None),
                };
                LanPeerStatus {
                    device_id: peer.device_id,
                    device_name: peer.device_name,
                    online,
                    handoff_ready,
                    host,
                    port,
                    last_seen,
                    pinned: peer.pinned,
                }
            })
            .collect();

        out.sort_by(|a, b| {
            b.handoff_ready
                .cmp(&a.handoff_ready)
                .then_with(|| b.online.cmp(&a.online))
                .then_with(|| a.device_name.cmp(&b.device_name))
        });
        Ok(out)
    }

    pub fn is_running(&self) -> bool {
        self.inner.lock().running
    }

    pub fn refresh_local_iroh_advertise(
        &self,
        app: &AppHandle,
        iroh_dial_addrs: &[SocketAddr],
    ) -> Result<(), DiscoveryError> {
        if !self.is_running() {
            return Ok(());
        }
        let listen_port = {
            let inner = self.inner.lock();
            if inner.local_iroh_dial_addrs.as_slice() == iroh_dial_addrs {
                return Ok(());
            }
            inner.listen_port
        };
        self.reregister_listen_port(app, listen_port, iroh_dial_addrs)
    }

    pub fn peer_iroh_dial_addrs(&self, device_id: &str) -> Vec<SocketAddr> {
        self.drain_browse_events();
        let inner = self.inner.lock();
        inner
            .seen
            .get(device_id)
            .map(|s| s.iroh_dial_addrs.clone())
            .unwrap_or_default()
    }

    pub fn emit_peer_updates_if_changed(&self, app: &AppHandle) {
        let Ok(peers) = self.peer_statuses(app) else {
            return;
        };
        let mut inner = self.inner.lock();
        if peers == inner.last_emitted_peers {
            return;
        }
        inner.last_emitted_peers = peers.clone();
        drop(inner);
        let _ = app.emit("p2p:discovery-update", serde_json::json!({ "peers": peers }));
    }

    fn advance_handoff_stable_samples(&self) {
        let now = now_secs();
        let mut inner = self.inner.lock();
        let local_device_id = inner.local_device_id.clone();
        for (device_id, seen) in inner.seen.iter_mut() {
            if device_id == &local_device_id {
                continue;
            }
            if seen.stable_samples >= HANDOFF_PORT_STABLE_SAMPLES || seen.stable_samples == 0 {
                continue;
            }
            if !is_ipv4_literal(&seen.host) || seen.port == 0 {
                continue;
            }
            if !Self::peer_is_online(seen, now) {
                continue;
            }
            let prev = seen.stable_samples;
            seen.stable_samples =
                (seen.stable_samples + 1).min(HANDOFF_PORT_STABLE_SAMPLES);
            if prev + 1 >= HANDOFF_PORT_STABLE_SAMPLES {
                eprintln!(
                    "[suchconfig-p2p] peer {device_id} handoff endpoint stable at {}:{} ({}/{HANDOFF_PORT_STABLE_SAMPLES} samples)",
                    seen.host, seen.port, seen.stable_samples
                );
            }
        }
    }
}

fn discovery_poll_loop(app: AppHandle, manager: DiscoveryManager) {
    loop {
        manager.drain_browse_events();
        manager.advance_handoff_stable_samples();

        {
            let inner = manager.inner.lock();
            if !inner.running {
                break;
            }
        }

        manager.emit_peer_updates_if_changed(&app);

        std::thread::sleep(Duration::from_millis(1200));
    }
}

fn instance_id_from_fullname(fullname: &str) -> String {
    fullname.split('.').next().unwrap_or("").to_string()
}

fn now_secs() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn mdns_registration_hostname(device_id: &str) -> String {
    let raw = hostname::get()
        .ok()
        .and_then(|h| h.into_string().ok())
        .unwrap_or_else(|| "suchconfig".to_string());

    let mut label = raw.trim().trim_end_matches('.').to_string();
    if let Some(stripped) = label.strip_suffix(".local") {
        label = stripped.to_string();
    }

    let label: String = label
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect();

    let label = label.trim_matches('-');
    let label = if label.is_empty() {
        "suchconfig"
    } else {
        label
    };

    let suffix: String = device_id
        .chars()
        .filter(|c| *c != '-')
        .take(8)
        .collect();

    let host_label = if suffix.is_empty() {
        label.to_string()
    } else {
        format!("{label}-{suffix}")
    };

    format!("{host_label}.local.")
}

fn parse_resolved_service(info: &ServiceInfo) -> Option<ParsedResolved> {
    let device_id = info.get_property_val_str("device_id")?.trim().to_string();
    if device_id.is_empty() {
        return None;
    }

    let srv_port = info.get_port();
    let txt_port = info
        .get_property_val_str("listen_port")
        .and_then(|s| s.trim().parse::<u16>().ok())
        .filter(|p| *p > 0);
    let port = match txt_port {
        Some(tp) if tp != srv_port => {
            eprintln!(
                "[suchconfig-p2p] peer {device_id} mDNS port mismatch txt={tp} srv={srv_port}; using srv"
            );
            srv_port
        }
        Some(tp) => tp,
        None => srv_port,
    };

    let mut host = select_connect_host(info);
    if host.is_empty() {
        if let Some(txt_ipv4) = info
            .get_property_val_str("lan_ipv4")
            .map(str::trim)
            .filter(|s| is_ipv4_literal(s))
        {
            host = txt_ipv4.to_string();
            eprintln!(
                "[suchconfig-p2p] peer {device_id} mDNS resolved port {port} using TXT lan_ipv4 {host}"
            );
        } else {
            let addrs: Vec<_> = info.get_addresses().iter().map(|a| a.to_string()).collect();
            eprintln!(
                "[suchconfig-p2p] peer {device_id} mDNS resolved port {port} without IPv4 (addresses={addrs:?}; link-local IPv6 is not usable for LAN handoff)"
            );
        }
    }

    let presence_only = info
        .get_property_val_str("transport")
        .map(|s| s.trim() == "iroh")
        .unwrap_or(false);

    let iroh_dial_addrs = info
        .get_property_val_str("iroh_addrs")
        .map(parse_iroh_dial_addrs_txt)
        .unwrap_or_default();

    Some(ParsedResolved {
        device_id,
        port,
        host,
        presence_only,
        iroh_dial_addrs,
    })
}

fn format_iroh_dial_addrs_txt(addrs: &[SocketAddr]) -> String {
    addrs
        .iter()
        .filter(|addr| addr.ip().is_ipv4())
        .map(|addr| addr.to_string())
        .collect::<Vec<_>>()
        .join(",")
}

fn parse_iroh_dial_addrs_txt(raw: &str) -> Vec<SocketAddr> {
    raw.split(',')
        .filter_map(|part| part.trim().parse::<SocketAddr>().ok())
        .filter(|addr| addr.ip().is_ipv4())
        .collect()
}

fn register_suchconfig_service(
    daemon: &ServiceDaemon,
    identity: &DeviceIdentity,
    listen_port: u16,
    seed_ipv4: &str,
    iroh_dial_addrs: &[SocketAddr],
) -> Result<u16, DiscoveryError> {
    let hostname = mdns_registration_hostname(&identity.record.device_id);
    let (srv_port, listen_port_txt) = if listen_port == 0 {
        (IROH_MDNS_PRESENCE_PORT, String::from("0"))
    } else {
        (listen_port, listen_port.to_string())
    };
    let mut properties: Vec<(&str, &str)> = vec![
        ("device_id", identity.record.device_id.as_str()),
        ("device_name", identity.record.device_name.as_str()),
        ("listen_port", listen_port_txt.as_str()),
        ("v", "1"),
    ];
    if listen_port == 0 {
        properties.push(("transport", "iroh"));
        properties.push((
            "iroh_endpoint_id",
            identity.record.public_key_b64.as_str(),
        ));
    }
    let iroh_addrs_txt = format_iroh_dial_addrs_txt(iroh_dial_addrs);
    if listen_port == 0 && !iroh_addrs_txt.is_empty() {
        properties.push(("iroh_addrs", iroh_addrs_txt.as_str()));
    }
    if !seed_ipv4.is_empty() {
        properties.push(("lan_ipv4", seed_ipv4));
    }

    let service_info = ServiceInfo::new(
        SERVICE_TYPE,
        &identity.record.device_id,
        &hostname,
        seed_ipv4,
        srv_port,
        &properties[..],
    )
    .map_err(|e| DiscoveryError::Mdns(e.to_string()))?
    .enable_addr_auto();

    daemon
        .register(service_info)
        .map_err(|e| DiscoveryError::Mdns(e.to_string()))?;

    Ok(srv_port)
}

fn select_connect_host(info: &ServiceInfo) -> String {
    let mut v4: Vec<Ipv4Addr> = info
        .get_addresses()
        .iter()
        .filter_map(|ip| match ip {
            IpAddr::V4(v4) => Some(*v4),
            IpAddr::V6(_) => None,
        })
        .collect();
    v4.sort_by_key(|ip| !is_private_ipv4(ip));
    v4.first().map(|ip| ip.to_string()).unwrap_or_default()
}

fn guess_local_lan_ipv4() -> Option<Ipv4Addr> {
    let sock = UdpSocket::bind("0.0.0.0:0").ok()?;
    for target in [
        "192.168.255.255:9",
        "10.255.255.255:9",
        "172.31.255.255:9",
    ] {
        if sock.connect(target).is_err() {
            continue;
        }
        let IpAddr::V4(v4) = sock.local_addr().ok()?.ip() else {
            continue;
        };
        if is_private_ipv4(&v4) && !v4.is_loopback() {
            return Some(v4);
        }
    }
    None
}

fn is_private_ipv4(ip: &Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 10
        || (o[0] == 172 && (16..=31).contains(&o[1]))
        || (o[0] == 192 && o[1] == 168)
}

fn is_ipv4_literal(host: &str) -> bool {
    host.parse::<Ipv4Addr>().is_ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn mdns_hostname_ends_with_local_suffix() {
        let host = mdns_registration_hostname("a1b2c3d4-e5f6-7890-abcd-ef1234567890");
        assert!(host.ends_with(".local."));
        assert_ne!(host, ".local.");
    }

    #[test]
    fn mdns_hostname_sanitizes_machine_name() {
        let host = mdns_registration_hostname("device-id");
        assert!(!host.contains(' '));
        assert!(host.ends_with(".local."));
    }

    #[test]
    fn peer_online_uses_found_and_resolved_grace() {
        let now = 1_000_000;
        let ready = SeenPeer {
            host: "192.168.1.10".into(),
            port: 42_000,
            last_found: now,
            last_resolved: now - 60,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&ready, now));
        assert!(DiscoveryManager::handoff_ready(&ready, now, false));
        assert!(!DiscoveryManager::handoff_ready(&ready, now, true));

        let single_sample = SeenPeer {
            host: "192.168.1.10".into(),
            port: 42_000,
            last_found: now,
            last_resolved: now,
            stable_samples: 1,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&single_sample, now));
        assert!(!DiscoveryManager::handoff_ready(&single_sample, now, false));

        let found_only = SeenPeer {
            host: String::new(),
            port: 0,
            last_found: now,
            last_resolved: 0,
            stable_samples: 0,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&found_only, now));
        assert!(!DiscoveryManager::handoff_ready(&found_only, now, false));

        let stale = SeenPeer {
            host: "192.168.1.10".into(),
            port: 42_000,
            last_found: now - FOUND_ONLINE_SECS - 1,
            last_resolved: now - OFFLINE_AFTER_SECS - 1,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(!DiscoveryManager::peer_is_online(&stale, now));
        assert!(!DiscoveryManager::handoff_ready(&stale, now, false));

        let online_stale_resolve = SeenPeer {
            host: "192.168.1.10".into(),
            port: 42_000,
            last_found: now,
            last_resolved: now - FOUND_ONLINE_SECS - 1,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&online_stale_resolve, now));
        assert!(DiscoveryManager::handoff_ready(&online_stale_resolve, now, false));

        let resolve_too_stale = SeenPeer {
            host: "192.168.1.10".into(),
            port: 42_000,
            last_found: now,
            last_resolved: now - RESOLVED_MAX_AGE_SECS - 1,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&resolve_too_stale, now));
        assert!(!DiscoveryManager::handoff_ready(&resolve_too_stale, now, false));

        let ipv6_link_local = SeenPeer {
            host: "fe80::c7f:b039:6f4a:ee1d".into(),
            port: 42_000,
            last_found: now,
            last_resolved: now,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: false,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&ipv6_link_local, now));
        assert!(!DiscoveryManager::handoff_ready(&ipv6_link_local, now, false));
        assert!(!DiscoveryManager::handoff_ready(
            &SeenPeer {
                host: "imac-lan-f20c5301.local".into(),
                port: 42_000,
                last_found: now,
                last_resolved: now,
                stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
                presence_only: false,
            iroh_dial_addrs: Vec::new(),
            },
            now,
            false
        ));

        let iroh_presence = SeenPeer {
            host: "192.168.1.10".into(),
            port: IROH_MDNS_PRESENCE_PORT,
            last_found: now,
            last_resolved: now,
            stable_samples: HANDOFF_PORT_STABLE_SAMPLES,
            presence_only: true,
            iroh_dial_addrs: Vec::new(),
        };
        assert!(DiscoveryManager::peer_is_online(&iroh_presence, now));
        assert!(DiscoveryManager::handoff_ready(&iroh_presence, now, false));
    }

    #[test]
    fn parse_iroh_dial_addrs_txt_roundtrip() {
        let addrs = vec![
            "192.168.9.188:41641".parse().unwrap(),
            "10.0.0.5:12345".parse().unwrap(),
        ];
        let txt = format_iroh_dial_addrs_txt(&addrs);
        assert_eq!(parse_iroh_dial_addrs_txt(&txt), addrs);
    }

    #[test]
    fn is_ipv4_literal_rejects_non_ipv4_hosts() {
        assert!(is_ipv4_literal("192.168.9.188"));
        assert!(!is_ipv4_literal("fe80::1"));
        assert!(!is_ipv4_literal("imac-lan-f20c5301.local"));
        assert!(!is_ipv4_literal(""));
    }

    #[test]
    fn is_private_ipv4_matches_lan_ranges() {
        assert!(is_private_ipv4(&Ipv4Addr::new(192, 168, 9, 188)));
        assert!(is_private_ipv4(&Ipv4Addr::new(10, 0, 0, 5)));
        assert!(!is_private_ipv4(&Ipv4Addr::new(8, 8, 8, 8)));
    }
}
