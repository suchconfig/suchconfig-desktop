# Trusted Folder Sync

> **Entitlement: Free (open-core)** — full Trusted Folder automation stays free forever. Complements free LAN Wi‑Fi P2P; Pro sells Sentinel + Broker, not basic multi-device backup. See [public-alpha-roadmap.md](../public-alpha-roadmap.md).

Local-first encrypted backups of the **Projects** and **Secrets** vaults to a user-chosen folder (Dropbox, iCloud Drive, Google Drive, NAS, or any writable path). SuchConfig does not host vault data; the desktop app watches sync files and merges changes across devices.

## What gets synced

| Data | Included in `.loro.enc`? | Notes |
|------|--------------------------|-------|
| **Project folders** (name, description, tags, link settings) | Yes — `projects.loro.enc` | Upserted by **name** on import; folder IDs remapped for items |
| **Project vault items** (CRDT notes/files in SQLite) | Yes — `projects.loro.enc` | Upserted by `(folder_id, title)` |
| **Secrets vault items** | Yes — `secrets.loro.enc` | Upserted by `(folder_id, title)` |
| Linked project **files on disk** | No | Handled by `LinkedProjectSync`, not Trusted Folder |
| Manual `.suchvault` archives | No | Separate export flow |

Backups are **full vault snapshots**, not per-change deltas. Every sync re-exports all folders/items for the affected vault from SQLite, encrypts, and atomically replaces the on-disk `.enc` file.

## Architecture

| Layer | Responsibility |
|-------|----------------|
| **Elixir** (`SuchConfigDesktop.TrustedFolder`) | JSON sync bundles: export/import project folders + vault items from SQLite |
| **Phoenix** (`TrustedFolderEvents`, `AppLive`) | Onboarding, badge, sync orchestration, PubSub, import on external change |
| **Tauri** (`trusted_folder.rs`, `trusted_folder_watcher.rs`) | Folder picker, config, `notify` watcher, Argon2id + AES-GCM `.loro.enc` files, IPC |
| **JS** (`TrustedFolderSync`, `GlobalPasskeyNative` in `app.js`) | `invoke` bridge, Tauri event → LiveView events, passes session master key to Rust |

**Important:** Loro/CRDT editing lives in the Elixir NIF, not in Rust. Rust stores encrypted transport blobs; Phoenix packs and unpacks SQLite rows.

### End-to-end export pipeline

```
Local change (save / create project / startup / unlock)
  → TrustedFolder.export_bundle/1          (Elixir: JSON snapshot)
  → push_event "trusted_folder_push_sync"    (LiveView → JS hook)
  → trusted_folder_register_snapshot       (Rust: in-memory cache per vault)
  → force_sync_trusted_folder              (Rust: encrypt + atomic write)
  → emit "trusted-folder:synced"           (Tauri → LiveView flash + badge refresh)
```

Import (external device or cloud sync) runs in reverse: watcher debounce → decrypt → `trusted-folder:import-snapshot` → `TrustedFolder.import_bundle/2`.

### Sync bundle format (`suchconfig_trusted_sync` v1)

**Projects** bundle includes both `folders` and `items`:

```json
{
  "format": "suchconfig_trusted_sync",
  "format_version": 1,
  "vault": "projects",
  "exported_at": "2026-06-06T12:00:00Z",
  "folders": [
    {
      "id": 1,
      "name": "my-app",
      "description": "",
      "tags": "",
      "linked_project_path": null,
      "linked_sync_enabled": false,
      "linked_auto_sync": false
    }
  ],
  "items": [
    {
      "title": "README",
      "kind": "generic_note",
      "security_mode": "global_passkey",
      "project_folder_id": 1,
      "crdt_snapshot_encrypted": "<base64>",
      "crdt_snapshot_hash": "...",
      "crdt_encryption_version": 1,
      "crdt_schema_version": 1
    }
  ]
}
```

**Secrets** bundle contains `items` only (uses `secrets_vault_folder_id` instead of `project_folder_id`).

Import behavior:

- **Folders:** upsert by unique `name`; build `exported_id → local_id` map for item remapping.
- **Items:** upsert by `(folder_id, title)` using remapped folder IDs.
- **Prune:** after upsert, local folders/items **missing from the snapshot are deleted** so each device mirrors the backup file (snapshot-authoritative sync).
- Bundles without a `folders` key (legacy) still import items using raw `project_folder_id` values; folder prune uses an empty folder list in that case.

Each item row still carries encrypted CRDT snapshot bytes — import replaces the stored blob for matching keys. This is **not** a live Loro op-log merge across concurrent edits to the same item title; the newest imported snapshot wins for that key.

### On-disk layout (Trusted Folder)

```
{user_chosen_path}/
  .suchconfig/
    projects.loro.enc
    projects.loro.sha256
    secrets.loro.enc
    secrets.loro.sha256
```

Checksum sidecars use Rust `Path::with_extension("sha256")`, so the sidecar for `projects.loro.enc` is **`projects.loro.sha256`** (not `projects.loro.enc.sha256`).

These are binary encrypted blobs — not browsable vault items. In macOS Finder, `.suchconfig` is a hidden dot-folder (⌘⇧. to reveal).

Legacy/plain names referenced in setup hints: `projects.suchvault`, `secrets.suchvault`.

Config: app data dir `trusted_folder.json` (`trusted_folder_path`, `setup_completed_at`).

## When sync runs

Sync requires **`ready_to_sync?/1`**: trusted folder configured, watcher running, and **vault unlocked**.

| Trigger | Scope | Module / path |
|---------|-------|----------------|
| **App load** (once per session) | Full (`projects` + `secrets`) | `apply_status/2` → `push_startup_sync_if_ready/3` after `get_trusted_folder` |
| **Vault unlock** | Full | `AppLive` `:vault_unlocked` / `vault_key_stored` → `push_full_sync_if_ready/1` |
| **Trusted Folder setup** | Full | `handle_setup_complete/2` → `push_full_sync/1` |
| **Backups missing** while unlocked | Full | `maybe_push_backup_if_missing/4` |
| **Project folder create / rename / delete** | Projects only | `ProjectsLive.FolderEvents` or `ProjectVaultLive.FolderEvents` → `notify_projects_changed/1` |
| **Project vault item save** | Projects only | `ProjectVaultLive.VaultItemEvents` → `broadcast_sync/2` |
| **Secrets entry save** | Secrets only | `SecretsVaultLive.EntryEvents` → `broadcast_sync/2` |
| **Manual** | Full | Settings **Sync now** or `force_sync_trusted_folder_ui` event |
| **Item/folder delete** | Projects / Secrets | Re-export after delete so removals propagate to backup |

**Startup sync** runs once per LiveView session (`trusted_folder_startup_sync_done`) when status is fetched — even if yesterday's `.enc` files already exist — so local changes made offline are pushed on next launch.

**Incremental saves** export one vault, but Rust `force_sync` writes each vault independently: registered snapshots are encrypted to disk; vaults without a registered in-memory snapshot are skipped (no longer fails the whole sync).

### `notify_projects_changed/1` routing

- **`AppLive` socket** (Projects page create): if `ready_to_sync?`, calls `push_single_vault_sync/2` directly.
- **Embedded `ProjectVaultLive`**: broadcasts `{:trusted_folder_sync, "projects"}` on `vault:{session_id}`; `AppLive` handles it when `vault_unlocked`.

Both folder event modules call this helper: `ProjectsLive.FolderEvents` (home/projects grid) and `ProjectVaultLive.FolderEvents` (in-vault sidebar).

## User flows

1. **First launch (no path):** After unlock overlay is dismissed or skipped, onboarding modal offers “Choose Trusted Folder”. Deferred while `show_unlock_overlay` is true.
2. **Setup:** Native folder dialog → `.suchconfig` created → watcher started → initial full export from LiveView.
3. **Unlock:** Touch ID / passkey → vault key in session registry + SQLite → optional Keychain/file backfill → full sync if trusted folder ready.
4. **Ongoing:** Triggers above → export bundle → `trusted_folder_push_sync` (with optional `master_key`) → Rust encrypt + atomic write.
5. **External change:** Watcher debounce (500ms) → decrypt + verify checksum → `trusted-folder:import-snapshot` → `TrustedFolder.import_bundle/2`.
6. **Topbar / Settings badge:** Path (`~` shortened home) plus backup state suffix.
7. **Settings → Sync health:** **Sync now**, **Verify archive integrity**, inline error/integrity messages (PubSub keeps Settings in sync with `AppLive`).

### Badge states

| Suffix | Meaning |
|--------|---------|
| **✓ Backed up** | Watcher running **and** both `projects.loro.enc` and `secrets.loro.enc` exist on disk |
| **· Watching** | Watcher running, but one or both `.enc` files missing |
| **· Paused** | Watcher not running |

Badge element IDs: `trusted-folder-status-badge` (topbar), `trusted-folder-settings-badge` (settings) — must remain unique in the DOM.

## Phoenix LiveView

### Modules and files

| Path | Role |
|------|------|
| `lib/suchconfig_desktop/trusted_folder.ex` | `export_bundle/1`, `import_bundle/2`, folder + item payloads |
| `lib/suchconfig_desktop_web/live/trusted_folder_events.ex` | Assigns, sync orchestration, PubSub, `ready_to_sync?/1` |
| `lib/suchconfig_desktop_web/live/app_live.ex` | Root UI, `handle_info` sync, hook hosts |
| `lib/suchconfig_desktop_web/live/project_vault_live/folder_events.ex` | In-vault project folder CRUD → sync |
| `lib/suchconfig_desktop_web/live/projects_live/folder_events.ex` | Projects page folder CRUD → sync |
| `lib/suchconfig_desktop_web/components/sc/trusted_folder_modal.ex` | Onboarding |
| `lib/suchconfig_desktop_web/components/sc/trusted_folder_badge.ex` | Status pill |

### LiveView events (client → server)

| Event | When |
|-------|------|
| `trusted_folder_status` | After `get_trusted_folder` (mount / reconnect) |
| `trusted_folder_setup_complete` | Tauri `trusted-folder:setup-complete` |
| `trusted_folder_setup_done` / `trusted_folder_setup_failed` | JS setup invoke result |
| `trusted_folder_import_snapshot` | External `.enc` change |
| `trusted_folder_request_initial_export` | Rust needs first export |
| `trusted_folder_synced` | Export write finished |
| `begin_trusted_folder_setup` | Modal CTA |
| `dismiss_trusted_folder_modal` | Modal dismiss |
| `open_trusted_folder_setup` | Re-open onboarding |
| `force_sync_trusted_folder_ui` | Manual full export (AppLive) |
| `trusted_folder_sync_now` | Settings → PubSub → AppLive |
| `trusted_folder_verify_integrity` | Settings → PubSub → verify IPC |
| `trusted_folder_sync_failed` | JS sync/verify error |
| `trusted_folder_verify_result` | JS integrity report |

### Server → client (`push_event`)

| Event | Hook | Purpose |
|-------|------|---------|
| `fetch_trusted_folder` | `TrustedFolderSync` | Load path, watcher, `.enc` presence/size |
| `invoke_setup_trusted_folder` | `TrustedFolderSync` | Native folder picker |
| `trusted_folder_push_sync` | `TrustedFolderSync` | Register snapshots + `force_sync` (includes `master_key` when unlocked) |
| `verify_trusted_folder_integrity` | `TrustedFolderSync` | SHA-256 + optional decrypt check (includes `master_key` when unlocked) |
| `run_native_global_passkey_auth` | `GlobalPasskeyNative` | Touch ID (unlock); separate from sync |

### PubSub

| Topic | Message | Effect |
|-------|---------|--------|
| `trusted_folder:status` | `{:trusted_folder_status, params}` | Settings badge updates |
| `vault:{session_id}` | `{:trusted_folder_sync, "projects" \| "secrets"}` | `AppLive` exports vault (if unlocked) |
| `vault:{session_id}` | `:vault_unlocked` | Unlock UI + `push_full_sync_if_ready` |

Child LiveViews (`SettingsLive`, `ProjectVaultLive`, `SecretsVaultLive`) subscribe to `vault:{session_id}` and **ignore** `{:trusted_folder_sync, _}` — only `AppLive` performs the export/push.

## JS hooks (`app.js`)

Phoenix allows **one hook name per DOM element**. Do not use `phx-hook="A B C"` on a single node.

`AppLive` hosts separate hidden elements under `#app-live-root`:

| Element ID | Hook |
|------------|------|
| `app-hook-vault-key-store` | `VaultKeyStore` |
| `app-hook-command-palette-hotkey` | `CommandPaletteHotkey` |
| `app-hook-trusted-folder-sync` | `TrustedFolderSync` |
| `app-hook-global-passkey-native` | `GlobalPasskeyNative` |

`TrustedFolderSync` registers `this.handleEvent/2` in `mounted()` for server `push_event`s. On `trusted_folder_push_sync`, it passes `masterKey` from the payload to `force_sync_trusted_folder` so Rust can encrypt when Keychain/file lookup alone fails (e.g. key only in SQLite/session after unlock).

## Tauri IPC

Managed state: `TrustedFolderAppState` (`.manage()` in `src-tauri/src/lib.rs`).

| Command | Purpose |
|---------|---------|
| `setup_trusted_folder` | Picker + config + auto-start watcher |
| `get_trusted_folder` | Path, sync dir, watcher, `.enc` paths/presence/byte sizes |
| `verify_trusted_folder_integrity` | Per-vault checksum (+ decrypt when `masterKey` provided) |
| `get_trusted_folder_path` | Path string only (legacy) |
| `force_sync_trusted_folder` | Encrypt + atomic write (optional `masterKey`) |
| `trusted_folder_vault_changed` | Force sync after vault change notification |
| `write_trusted_sync_archive` | Write base64 payload under `.suchconfig/` (path-validated) |
| `start_trusted_folder_watcher` | `notify` on `*.loro.enc` (500ms debounce) |
| `stop_trusted_folder_watcher` | Stop watcher |
| `trusted_folder_register_snapshot` | Cache Phoenix export (`vault`: `secrets` \| `projects`) |
| `trusted_folder_notify_vault_updated` | Register + write `.enc` |

Optional `setup_trusted_folder` args: `projectsArchiveBase64`, `secretsArchiveBase64`. If omitted, Rust emits `trusted-folder:request-initial-export`.

### Tauri → webview events

| Event | LiveView event |
|-------|----------------|
| `trusted-folder:setup-complete` | `trusted_folder_setup_complete` |
| `trusted-folder:request-initial-export` | `trusted_folder_request_initial_export` |
| `trusted-folder:import-snapshot` | `trusted_folder_import_snapshot` |
| `trusted-folder:synced` | `trusted_folder_synced` |

### Crypto and master key

Envelope: `SCENC01`, Argon2id-derived AES-256-GCM. SHA-256 sidecars beside each `.enc` file.

Master key resolution order in Rust (`resolve_master_key/3`):

1. **`masterKey` from LiveView** (session registry or SQLite via Phoenix — passed on each sync while unlocked)
2. **macOS Keychain** — service `suchconfig.project_manager`, account `suchconfig.project_manager.vault` (legacy `vault_master` also tried)
3. **App data file** — `{app_data_dir}/suchconfig_vault_key`
4. **Home fallback** — `~/.suchconfig/suchconfig_vault_key`

On unlock, Phoenix also pushes `store_vault_key` so Keychain/file are backfilled for future Rust-only reads.

Full threat model: [secure-encryption.md](./secure-encryption.md).

**Startup:** If `trusted_folder_path` is set, `lib.rs` `setup` calls `try_auto_start_watcher`.

## Verifying sync manually

**In app:** Settings → **Sync health** → **Verify archive integrity** (requires Trusted Folder configured; unlock vault for decrypt verification).

**On disk:**

```bash
ls -la "/path/to/your/trusted-folder/.suchconfig/"
```

Expect non-zero byte sizes for both `.loro.enc` files after unlock. Use exact byte counts (`ls -la`), not rounded `ls -h` sizes — small changes may not change the displayed KB.

Sync/import errors surface in Settings (inline) and flash toasts; JS also logs to the webview console.

## Testing

```bash
cd phoenix-app && mix test test/suchconfig_desktop/trusted_folder_test.exs
cd phoenix-app && mix test test/suchconfig_desktop_web/live/trusted_folder_events_test.exs
cd phoenix-app && mix test test/suchconfig_desktop_web/components/sc/trusted_folder_badge_test.exs
cd phoenix-app && mix test test/suchconfig_desktop_web/components/sc/trusted_folder_modal_test.exs
cd phoenix-app && mix test test/suchconfig_desktop_web/live/app_live_test.exs
cd src-tauri && cargo test trusted_folder
```

## Limitations / follow-ups

- Concurrent edits to the **same item title** on two devices: last imported snapshot wins (not Loro op-log merge).
- Secrets vault folders are not yet exported separately (items only; folder IDs must align across devices).
- Onboarding waits until unlock overlay is cleared.
- `ProjectVaultLive` still uses `phx-hook="VaultKeyStore LinkedProjectSync"` on one element — should be split like `AppLive` if both hooks must run.
- Versioned archive history (keep last N `.enc` files) — not yet implemented.
- Per-item “exclude from Trusted Folder” flag — not yet implemented.
- Merge audit events for trusted-folder import — not yet wired.
