# Security Policy

## Supported versions

| Version | Supported |
| --- | --- |
| Public Alpha (`0.1.0-alpha.x`) | Yes — best-effort |
| Pre-alpha / untagged local builds | No formal support |

Report issues against the latest Public Alpha release when possible.

## Product security posture

SuchConfig Desktop is **local-first**:

- Vault data (SQLite + encrypted Loro snapshots) stays on the device.
- **Argon2id** unlock + **AES-GCM** item encryption protect data at rest.
- Vault load / save / merge does **not** send vault bytes to SuchConfig servers.
- Network use for the vault plane is limited to user actions such as optional license verification, app updates, and **opt-in** LAN P2P between paired devices.
- **Trusted Folder** writes encrypted snapshots to a folder **you** choose (iCloud / Dropbox / NAS / USB) — not a SuchConfig-hosted vault API.
- Planned **Vault Importer** (not in Public Alpha) will parse and persist **on-device only**. Treat any manager export files as hot secrets; delete them after use.

## LAN P2P

Wi‑Fi / LAN sync is **opt-in**, **same-LAN only**, and requires **explicit pairing** before replication.

Authoritative detail: [docs/security/p2p-wifi-sync-security.md](docs/security/p2p-wifi-sync-security.md).

Public Alpha maturity: pairing + Handoff are dogfood-verified; incremental delta sync and some transport confidentiality hardening remain open. Do not assume finished LAN Wi‑Fi sync security until those items land and are documented.

## Reporting a vulnerability

Email **security@suchconfig.io** with:

- Affected version / platform (macOS version, build channel)
- Description and impact
- Reproduction steps or proof-of-concept (no public gist of vault dumps)
- Whether the issue involves P2P, importer exports, or unlock / keychain

You should receive an acknowledgment within **7 days**. We will coordinate disclosure after a fix or mitigation is available for Public Alpha users.

Please do **not** file public GitHub issues for security-sensitive reports.

## Out of scope (examples)

- Attacks that require malware with the user’s privileges on an unlocked session
- Compromise of an already-paired peer device
- Social engineering to obtain the vault passkey
- Issues solely in third-party password-manager export formats (report upstream when appropriate; we still welcome importer hardening PRs)

## Prefer private disclosure

If unsure whether a finding is security-relevant, email security@ first.
