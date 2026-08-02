# SuchConfig open core (Public Alpha)

SuchConfig Desktop is a **local-first Project Vault + Secrets Vault**. Configs and credentials stay on your device. Multi-device continuity is **user-owned** (Trusted Folder and optional LAN Wi‑Fi sync)—not a SuchConfig cloud vault.

**One-liner:** Open core audits the vault crypto and ships a free local vault with Trusted Folder and opt-in LAN sync as those layers mature.

> Public Alpha is under **heavy active development**. Features and UX will change between tags.

## Free (Apache-2.0 CE)

| Capability | Notes |
| --- | --- |
| Project Vault + Secrets Vault + `.suchvault` archives | Offline CRDT-backed store; still evolving |
| Trusted Folder | Encrypted snapshots to a folder you own (iCloud / Dropbox / NAS / USB) |
| LAN Wi‑Fi P2P | Opt-in same-LAN sync; pairing + Handoff verified; incremental deltas still in progress |
| Vault Importer | Planned Free on-device import — **not** in this alpha |

## What this repo is

- Auditable desktop CE + open `vault_core` (CRDT / crypto)
- Trusted Folder and LAN P2P transport you can read

## What this repo is not

- A cloud password manager or SuchConfig-hosted vault API
- A finished migration suite from other password managers
- Full history of private engineering (clean public start)
- SuchUtils parsers/generators (separate product)
- W3C DID / Verifiable Credentials (out of initial vision)
- Licensed Personal Pro engines (absent from this tree)

## Maturity

Public Alpha tag: **`v0.1.0-alpha.3`**. See [public-alpha-roadmap.md](./public-alpha-roadmap.md). Platform: **macOS primary**; Linux/Windows best-effort.

Pricing / Stripe storefront stays hidden during alpha; Free download + this GitHub tree are the public surface.
