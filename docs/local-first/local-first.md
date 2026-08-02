# Local-First Strategy for SuchConfig

## Core Philosophy

SuchConfig is built on a **local-first architecture** where vault data never leaves the machine unless the user explicitly exports or opts into a sync path they control. Inspired by local-first principles, SuchConfig prioritizes user ownership, privacy, and offline capability above all else.

Canonical product story: [data-sovereignty.md](../concepts/data-sovereignty.md) · [public-alpha-roadmap.md](../public-alpha-roadmap.md).

## Core Principles

### 1. Data Sovereignty

Project Vault and Secrets Vault load, save, merge, and index entirely on the user's device. Network use is limited to license verification, optional app updates, and **user-owned** sync (Trusted Folder, LAN P2P). This ensures:

- **Privacy**: Configs, secrets, and merge history remain private
- **Ownership**: Users maintain complete control over their vault
- **Compliance**: Meets strict data-protection expectations without a hosted vault

### 2. Offline-First Operation

SuchConfig is fully functional without internet connectivity. Users can:

- Unlock and edit CRDT-backed vault items offline
- Import/export encrypted `.suchvault` archives
- Use Trusted Folder sync against a local or mounted folder
- Operate in air-gapped or restricted network environments

### 3. Minimal Network Dependencies

The only network access required is for:

- **License Verification**: Periodic validation of Pro entitlements (configurable offline grace)
- **Application Updates**: Optional automatic updates or manual version upgrades
- **Opt-in local sync**: LAN Wi‑Fi P2P between paired devices the user controls — not a SuchConfig cloud vault

## User Experience

### Offline Workflow

- Launch without blocking network checks
- Edit vault items via Phoenix LiveView over the local Tauri/Rust core (`vault_core`)
- Persist encrypted Loro snapshots in local SQLite
- Export/import archives and Trusted Folder snapshots without a server

### Privacy-First Interface

- Clear indicators that vault bytes stay on-device
- Transparent about any network operations (updater, license, opt-in P2P)
- User controls for Trusted Folder path and LAN pairing
- No telemetry containing vault content

### Seamless Updates

- **Automatic Updates**: Background downloads with user approval before installation
- **Manual Updates**: User-initiated version checks and installations
- **Offline Updates**: Support for manual installation of update packages

## Security Benefits

- **No vault transmission by default**: Vault content does not traverse SuchConfig servers
- **Reduced attack surface**: Minimal network exposure for core vault operations
- **Local encryption**: Per-item encryption at rest; plaintext only transiently in memory
- **Local audit**: Merge audit and export-integrity metadata stay on device

## Technical Implementation

### Local Storage

- **SQLite**: Authoritative vault item rows and metadata
- **Encrypted Loro snapshots**: CRDT state in Rust (`suchconfig_vault_core`)
- **File system**: Trusted Folder and archive paths via Tauri APIs
- **No cloud dependency**: Core vault operates without SuchConfig-hosted storage

### Offline Capabilities

- Embedded `vault_core` NIF for encrypt / merge / archive hot paths
- Persistent local DB survives restarts
- Native OS integration for folders, keychain, and secure storage where applicable

### Update Strategy

- License checks are periodic and configurable
- Tauri updater with user-controlled preferences
- Application continues functioning during network outages

### Multi-Device Continuity (user-owned)

- **Trusted Folder**: Encrypted snapshots to iCloud / Dropbox / NAS / USB folders the user already owns
- **LAN Wi‑Fi P2P**: Opt-in pairing and Handoff between devices on the same network
- **Encrypted archives**: `.suchvault` handoff for teams and backups

None of these require a SuchConfig-hosted sync service.

## Competitive Advantages

### Versus Cloud Vaults

- **Privacy**: Default is on-device, not “in our cloud”
- **Performance**: No round-trip for load/save/merge
- **Reliability**: Works offline and in restricted networks
- **Migration**: Free on-device Vault Importer path from major managers (as formats ship)

### Versus Traditional Desktop Tools

- **Modern UI**: Phoenix LiveView inside Tauri
- **Cross-platform**: macOS primary; Linux/Windows best-effort
- **CRDT merges**: Intent-preserving collaboration without conflict dialogs
- **Open-core trust**: Auditable free CE for vault + local sync; Pro for Sentinel + Broker

## Related Documents

- [Data sovereignty](../concepts/data-sovereignty.md)
- [CRDT via Loro](./CRDT-via-Loro.md)
- [Trusted Folder sync](../features/trusted-folder-sync.md)
- [Public Alpha roadmap](../public-alpha-roadmap.md)

## Conclusion

SuchConfig Desktop’s local-first strategy positions it as a privacy-focused, reliable, user-controlled alternative to cloud password and config managers. Vault operations stay on-device; multi-device continuity uses folders and LAN paths the user owns — **powerful functionality without surrendering ownership**.
