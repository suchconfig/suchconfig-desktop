# Changelog

All notable changes to SuchConfig (public CE) are documented here.

Format based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/) with Public Alpha pre-release tags (`v1.0.0-alpha.N`).

## [1.0.0-alpha.8] — 2026-08-06

### Fixed

- Secrets Vault text fields: declare and forward `autocomplete` / `autocorrect` / `autocapitalize` / `spellcheck` on entry detail and new-entry components so `mix compile --warnings-as-errors` succeeds in CI

### Changed

- Public CI workflow: add `workflow_dispatch` so founders can run CI from the Actions UI when needed

## [1.0.0-alpha.7] — 2026-08-06

### Added

- On-device Vault Importer for Secrets Vault: password-manager JSON export → preview, duplicate keep/overwrite, Import all
- Secrets Vault folder settings (rename / delete with Deleted Items or permanent purge) and entry activity history
- Secrets Vault entry detail: secret bodies masked by default (including SSH) behind the reveal toggle

### Fixed

- New project with a selected folder: open Link Project preview and start the disk scan so import summary is reviewable before Confirm
- AI ignore scaffolds: detect stack from manifests / `.gitignore`, merge project-specific patterns, and surface duplicate folder-name errors in the New project modal

### Changed

- README: clearer local-first developer positioning for the Public Alpha CE
- Public Alpha status: first password-manager JSON import path is dogfood-ready; additional export formats remain planned

## [1.0.0-alpha.6] — 2026-08-02

### Fixed

- First-run vault unlock: Keychain / Tauri invoke args use camelCase (`keyId`, `wrappedKey`) so store/load matches the Rust command schema
- README app icon: use `src-tauri/icons/app-icon.svg` (public) instead of denylisted `design/` so GitHub renders it

### Added

- Keyboard chord shortcuts (including G / N sequences) with [keyboard shortcuts](docs/keyboard-shortcuts.md) docs
- Live vault storage stats on Settings
- Project grid lock affordances

### Changed

- Public branding: “SuchConfig Desktop” → **SuchConfig** across README, docs, and UI copy
- Public GitHub repo renamed to [`suchconfig/suchconfig-app`](https://github.com/suchconfig/suchconfig-app)

## [1.0.0-alpha.5] — 2026-08-02

### Added

- README section explaining why Elixir + Phoenix LiveView, Tauri 2, and Rust `vault_core` are split the way they are

## [1.0.0-alpha.4] — 2026-08-02

### Changed

- Public tag line moved from `v0.1.0-alpha.*` to `v1.0.0-alpha.*` (same Public Alpha maturity; clearer semver for CE snapshots)
- README authorship: Author section for [zanuka](https://github.com/zanuka); copyright line attributes Michael Delucchi

## [0.1.0-alpha.3] — 2026-08-01

### Fixed

- CE publish refreshes `phoenix-app/mix.lock` off Hex `zanukalabs/suchconfig_core` so GitHub Actions `mix deps.get` uses the vendored path dep only (no org auth)

## [0.1.0-alpha.2] — 2026-08-01

### Changed

- Slimmed Public Alpha docs: removed Pro vision docs (Sentinel / Local Broker) from CE allowlist
- Denylisted root `ROADMAP-such-utils.md` so it no longer ships on GitHub
- Softened public README / SECURITY / roadmap copy to focus on Free CE maturity

## [0.1.0-alpha.1] — 2026-08-01

### Added

- Public Alpha open-core snapshot: Project Vault + Secrets Vault (local-first, CRDT)
- Trusted Folder sync (Free)
- LAN Wi‑Fi P2P: pairing + Handoff (Free; incremental deltas still in progress)
- Vault Importer surface (Free; wizard incomplete — password-manager JSON import roadmap)
- Apache-2.0 LICENSE, CONTRIBUTING (DCO), CODE_OF_CONDUCT, SECURITY
- Public docs index, Public Alpha roadmap, issue templates, minimal GitHub Actions CI

### Notes

- Pricing page on suchconfig.io remains hidden during Public Alpha
- macOS is the primary supported platform; Linux / Windows are best-effort

[1.0.0-alpha.8]: https://github.com/suchconfig/suchconfig-app/releases/tag/v1.0.0-alpha.8
[1.0.0-alpha.7]: https://github.com/suchconfig/suchconfig-app/releases/tag/v1.0.0-alpha.7
[1.0.0-alpha.6]: https://github.com/suchconfig/suchconfig-app/releases/tag/v1.0.0-alpha.6
[1.0.0-alpha.5]: https://github.com/suchconfig/suchconfig-app/releases/tag/v1.0.0-alpha.5
[1.0.0-alpha.4]: https://github.com/suchconfig/suchconfig-app/releases/tag/v1.0.0-alpha.4
[0.1.0-alpha.3]: https://github.com/suchconfig/suchconfig-app/releases/tag/v0.1.0-alpha.3
[0.1.0-alpha.2]: https://github.com/suchconfig/suchconfig-app/releases/tag/v0.1.0-alpha.2
[0.1.0-alpha.1]: https://github.com/suchconfig/suchconfig-app/releases/tag/v0.1.0-alpha.1
