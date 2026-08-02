# SuchConfig Desktop

**Public Alpha** (`v0.1.0-alpha.3`) — local-first Project Vault + Secrets Vault.

> **Heavy active development.** This is the first public cut of the open-core CE. APIs, UX, and sync behavior will change. Expect rough edges; please read [Current status](#current-status) before depending on any path in production.

Open core lets you audit the vault crypto and run a free local vault with user-owned backup (Trusted Folder) and opt-in LAN sync as those layers mature.

| | |
| --- | --- |
| **License** | [Apache-2.0](LICENSE) |
| **Platform** | **macOS primary**; Linux / Windows best-effort |
| **Docs** | [docs/README.md](docs/README.md) · [Public Alpha roadmap](docs/public-alpha-roadmap.md) |
| **Releases** | [GitHub Releases](https://github.com/suchconfig/suchconfig-desktop/releases) |
| **Site** | [suchconfig.io](https://suchconfig.io) |

---

## Current status

| Area | Status |
| --- | --- |
| Project Vault + Secrets Vault (offline, CRDT) | Usable — dogfood; still evolving |
| Trusted Folder sync | Shipped — Free |
| LAN Wi‑Fi P2P | Pairing + Handoff verified; incremental deltas and firewall-ON hardening still open — **not** finished LAN sync |
| On-device vault importer | Planned — Free when formats ship; **not** in this alpha |
| Signed / notarized macOS builds | Stated honestly on download pages when published |
| Pricing | Hidden during Public Alpha |

Detail: [docs/public-alpha-roadmap.md](docs/public-alpha-roadmap.md) · [docs/open-core.md](docs/open-core.md)

---

## What ships free

| Capability | Notes |
| --- | --- |
| Project Vault + Secrets Vault + encrypted archives | Offline CRDT-backed store |
| **Trusted Folder** | User-owned folder backup / merge |
| **LAN Wi‑Fi P2P** | Opt-in, same LAN; maturity above |
| **Vault Importer** | On-device; when formats ship |

Never paywalled: Trusted Folder, LAN P2P, or Vault Importer (when it ships).

---

## What this is

A **local-first vault** for AI-augmented development: project configs, secrets, prompts, and encrypted archives on your machine — no SuchConfig-hosted vault database.

- **Tauri 2** shell + embedded **Phoenix LiveView** (`phoenix-app/`)
- Vault crypto / CRDT in open **`vault_core`** (vendored in public CE builds)
- Multi-device continuity is **user-owned** (folder you choose, or opt-in LAN sync)

**Not in this repo:** SuchUtils (parsers / generators — separate product).

---

## Quick start (developers)

**Prerequisites:** Rust ([rustup](https://rustup.rs/)), Node 18+, pnpm, Elixir / Erlang matching `phoenix-app/.tool-versions` (asdf recommended).

`mix` is only on your PATH after Elixir is installed **and** your shell has loaded asdf (or another Elixir install). Run Mix commands from **`phoenix-app/`**, not the repo root.

```bash
git clone https://github.com/suchconfig/suchconfig-desktop.git
cd suchconfig-desktop
pnpm install
cd phoenix-app
# confirm: which mix   # should print a path; if not, open a new login shell or install Elixir via asdf
mix deps.get
mix ecto.migrate
cd ..
pnpm run tauri:dev
```

Phoenix-only (browser): `cd phoenix-app && mix setup && mix phx.server` → [http://localhost:4000](http://localhost:4000).

Asset deps from repo root: `pnpm run phoenix-assets:install`.

> Public Alpha CE resolves Mix / Cargo against the **vendored** `vault_core` in this tree. Private founder builds may use vendored CE dependencies ship in-tree.

---

## Architecture (trust boundary)

```
SuchConfig Desktop
├── Tauri shell (Rust) — OS bridges, LAN P2P transport, passkey bridges
├── Phoenix LiveView — Project Vault + Secrets Vault UI, SQLite
└── vault_core — Loro CRDT + crypto (sole writer path for merge)
```

Vault load / save / merge does **not** use the network. Optional license checks and updater stay outside the vault trust boundary. See [SECURITY.md](SECURITY.md) and [P2P security](docs/security/p2p-wifi-sync-security.md).

---

## Why Elixir (and this stack)

**Elixir** is the primary application language because SuchConfig is a long-running local product: vault UI, domain logic, SQLite, and orchestration need fault-tolerant concurrency more than a single-process SPA. OTP supervision, immutable data, and `{:ok, _}` / `{:error, _}` pipelines keep product code explicit and crash-isolated inside the embedded BEAM sidecar.

| Layer | Role |
| --- | --- |
| **Elixir + Phoenix LiveView** | Product surface — Project Vault / Secrets Vault UI, forms, PubSub-driven updates, and most domain orchestration over local SQLite |
| **Tauri 2 (Rust shell)** | Desktop trust boundary — OS bridges, keychain / passkeys, file dialogs, LAN P2P transport, window lifecycle |
| **Rust (`vault_core`)** | Hot path — Loro CRDT merge, vault crypto, and encrypted archive packing (sole writer path for merge) |

LiveView keeps the UI server-driven with a thin client, so we ship less custom frontend state for a security-sensitive vault. Rust stays where systems work belongs (native APIs, crypto, CRDT). Elixir stays where product logic and realtime local UX belong. That split is intentional — not “Elixir for everything.”

---

## Database note

Dev (`pnpm run tauri:dev`) and installed release builds use **separate SQLite files**. Missing data after switching modes is usually two databases — not a sync bug. See docs under [docs/README.md](docs/README.md).

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) (DCO, conventional commits). Good first issues: docs, UX, tests.

Public Alpha is early: prefer issues and small docs/UX/test PRs. Expect breaking changes between alpha tags.

- [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- [SECURITY.md](SECURITY.md)
- [CHANGELOG.md](CHANGELOG.md)

---

## Author

Created by [zanuka](https://github.com/zanuka) (Mike Delucchi)

## License

Copyright © 2026 Mike Delucchi

Licensed under the [Apache License, Version 2.0](LICENSE).
