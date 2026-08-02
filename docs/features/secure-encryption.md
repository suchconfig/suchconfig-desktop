# Secure encryption

How SuchConfig protects vault data at rest, in sync folders, and in portable archives. This document is the security reference for engineers and reviewers; product flows live in [Global Passkey](./global-passkey.md), [Trusted Folder Sync](./trusted-folder-sync.md), and [Project Vault archives](./project-vault.md).

## Design principle

**One vault key** unlocks the app and encrypts Project/Secrets vault items in SQLite. **Optional second layers** wrap exports for transport:

| Transport | File | Key material |
|-----------|------|----------------|
| Local SQLite + session | `vault_items.crdt_snapshot_encrypted` | Vault key (Global Passkey) |
| Trusted Folder auto-sync | `.suchconfig/*.loro.enc` | Same vault key (outer envelope) |
| Manual archive export | `*.suchvault` | **User-chosen export password** (independent) |

SuchConfig does not host vault bytes. Ciphertext in a user’s Dropbox/iCloud/NAS is meant to be useless **without the vault key** (or, for `.suchvault`, without the export password).

---

## Vault key (Global Passkey)

After unlock, the app holds a **random 32-byte key** (hex-encoded for storage), keyed as `suchconfig.project_manager.vault` in Phoenix.

**Persistence (same key, three stores):**

1. **macOS Keychain** — `keyring`, service `suchconfig.project_manager`, account = `key_id`.
2. **Key files** — `suchconfig_vault_key` in app data dir and `~/.suchconfig/suchconfig_vault_key` (mode `0600` on Unix when written from Tauri).
3. **SQLite** — `vault_keys` via `SuchConfigDesktop.VaultKeyStore`.

**In-memory only until lock:** `VaultSessionRegistry` for the LiveView session. Lock removes the key from the registry; Keychain, files, and SQLite are **left intact** so the next unlock recovers the same key.

**Touch ID / device credential** gates **reading the key and using the app** (via `tauri-plugin-biometry` and Keychain access during unlock). It does **not** apply a separate passphrase to each `.loro.enc` file on disk.

See [global-passkey.md](./global-passkey.md) for unlock/lock UX and session behavior.

---

## Layer 1 — Vault items in SQLite (inner encryption)

Project Vault and Secrets Vault persist **encrypted CRDT snapshots** per item (`crdt_snapshot_encrypted` on `vault_items` / `secrets_vault_items`). Plaintext exists only transiently during edit/decrypt inside the app.

**Implementation:** `SuchConfigCore.Security.EnvCrypto` (`encrypt_to_binary` / `decrypt_from_binary`) with the **vault key** as the secret. Settings UI describes this layer as **XChaCha20-Poly1305** with **Argon2id** KDF (product copy; exact parameters live in **suchconfig-core**).

**Properties:**

- Per-item ciphertext in the local DB.
- Without the vault key, rows are opaque blobs (titles/metadata in SQL are not secret bodies).
- Decrypting an item requires the same key that was used when the item was saved.

---

## Layer 2 — Trusted Folder `.loro.enc` (sync transport)

Automatic sync writes encrypted blobs under the user’s chosen folder:

```
{trusted_folder}/.suchconfig/
  projects.loro.enc
  projects.loro.enc.sha256
  secrets.loro.enc
  secrets.loro.enc.sha256
```

The watcher only processes `projects.loro.enc` and `secrets.loro.enc` (not `*.suchvault` in that pipeline).

### Outer envelope (`SCENC01`)

Implemented in `src-tauri/src/trusted_folder_watcher.rs`:

| Field | Size | Role |
|-------|------|------|
| Magic | 7 bytes | `SCENC01` |
| Salt | 16 bytes | Random per file write |
| Nonce | 12 bytes | Random per file write |
| Ciphertext | variable | AES-256-GCM |

**Key derivation:** Argon2id (`Argon2::default()` in the Rust `argon2` crate — currently ~19 MiB memory cost, 2 iterations) over the **vault key bytes** and the file salt → 32-byte AES key.

**Integrity:** `.sha256` sidecar stores SHA-256 of the **ciphertext** (tamper detection on import; not secrecy).

**Atomic write:** Temp file + rename under `.suchconfig/`.

### Plaintext inside the envelope

Phoenix builds a JSON bundle (`suchconfig_trusted_sync` v1) via `SuchConfigDesktop.TrustedFolder.export_bundle/1`. Each item includes **already-encrypted** `crdt_snapshot_encrypted` from Layer 1. So sync uses **defense in depth**:

1. Outer `SCENC01` hides the bundle on Dropbox/etc.
2. Inner CRDT fields remain encrypted with the vault key even if the outer layer were broken.

Import decrypts the outer envelope in Rust, then Phoenix `import_bundle/2` upserts items by `(folder_id, title)`.

See [trusted-folder-sync.md](./trusted-folder-sync.md) for IPC and flows.

### Master key loading for sync

`load_master_key/2` reads, in order:

1. Keychain — service `suchconfig.project_manager`, account from watcher config (today often `vault_master`; Global Passkey stores under `suchconfig.project_manager.vault`).
2. App data `suchconfig_vault_key`.
3. `~/.suchconfig/suchconfig_vault_key`.

Sync therefore usually follows the **same key files** as unlock even if Keychain account names differ. Aligning Keychain `key_id` with Global Passkey is recommended for consistency.

---

## Layer 3 — Manual `.suchvault` archives (portable handoff)

**Export/import** in Project Vault uses `ProjectVault.Archive` + `EnvCrypto.pack_archive/2` with a **password the user enters at export time**. That password is **not** required to be the vault key.

- Format id `suchvault`, envelope version 3 (see `archive.ex`).
- Intended for email, USB, Git, or air-gapped handoff.
- Legacy v1/v2 archives remain readable on import.

Trusted Folder **may** seed `projects.suchvault` / `secrets.suchvault` during setup if base64 payloads are passed into `setup_trusted_folder`; **ongoing** sync uses `.loro.enc`, not `.suchvault`.

---

## Comparison

| Question | SQLite / CRDT | Trusted Folder `.loro.enc` | `.suchvault` export |
|----------|----------------|----------------------------|---------------------|
| What encrypts? | EnvCrypto + vault key | SCENC01 + vault key | EnvCrypto + **export password** |
| Typical location | App DB | User sync folder | Anywhere user copies file |
| Attacker needs | Vault key | Vault key | Export password |
| Touch ID role | Unlock to get key | Same (key for sync writes) | None (user types password) |

---

## Threat model: who can read what?

### Attacker has only synced `.loro.enc` files (e.g. compromised cloud account)

**Expected: cannot read vault content.** The file does not contain the vault key. AES-256-GCM with a high-entropy random key is not practically breakable without the key.

**May still learn:** file existence, sizes, modification times, path layout (`.suchconfig`), and that SuchConfig is in use.

### Attacker has `.enc` files **and** vault key material

**Can decrypt** outer sync bundles and recover inner JSON. Item bodies still require decrypting `crdt_snapshot_encrypted` with the same vault key (Layer 1).

Key material might come from: stolen laptop with Keychain backup, copied `suchconfig_vault_key`, SQLite DB exfiltration, or malware on an **unlocked** session.

### Attacker has only a `.suchvault` file

**Cannot read** without the **export password** chosen at export time. Independent of vault unlock state unless the user reused the same string (not recommended).

### Malware on unlocked Mac

**Can read vault data** while the session holds the key in memory and the app can decrypt. Encryption at rest does not help against a compromised running OS session.

---

## What is *not* protected by these layers

- **Metadata in SQL** — Folder names, item titles, kinds, tags (unless also encrypted elsewhere).
- **Separate sync password** — Trusted Folder does not add a second secret only for sync; it reuses the vault key.
- **Key files on disk** — Fallback key files are sensitive; protection relies on OS permissions, FDE, and physical access control.
- **Lock vs erase** — Lock clears in-memory key only; persisted Keychain/file/DB copies remain for re-unlock.
- **Argon2 strength on `.enc`** — Trusted Folder uses the `argon2` crate defaults, which are lighter than the “Argon2id · t=4 · m=64M” wording shown in Settings for the EnvCrypto stack. For random vault keys, **key secrecy** dominates, not KDF cost.

---

## Code references

| Layer | Location |
|-------|----------|
| Vault key store (Tauri) | `src-tauri/src/lib.rs` — `native_global_passkey_*` |
| Trusted Folder envelope | `src-tauri/src/trusted_folder_watcher.rs` — `encrypt_snapshot`, `decrypt_snapshot`, `load_master_key` |
| Sync bundle export/import | `phoenix-app/lib/suchconfig_desktop/trusted_folder.ex` |
| CRDT item encrypt | `phoenix-app/lib/suchconfig_desktop/project_vault.ex`, `secrets_vault.ex` — `EnvCrypto` |
| `.suchvault` pack | `phoenix-app/lib/suchconfig_desktop/project_vault/archive.ex` |

---

## Related docs

- [Global Passkey](./global-passkey.md) — unlock, Touch ID, key persistence
- [Trusted Folder Sync](./trusted-folder-sync.md) — watcher, IPC, file layout
- [Backup & recovery](./backup-recovery.md) — product narrative for user-owned backups
- [Data sovereignty](../concepts/data-sovereignty.md) — why ciphertext in your folder is acceptable
- [Project Vault CRDT usage](../local-first/project-vault-CRDT-usage.md) — Loro + EnvCrypto at the item layer

---

## Follow-ups (engineering)

- Unify Keychain `key_id` for Trusted Folder watcher (`vault_master`) with Global Passkey (`suchconfig.project_manager.vault`).
- Document exact `EnvCrypto` parameters in suchconfig-core and mirror them here.
- Optional: user-chosen **sync passphrase** distinct from vault key for Trusted Folder (stronger cloud-threat model, worse UX).
- Align Settings KDF copy with actual Argon2 params used in `SCENC01` if we harden sync KDF to match EnvCrypto.
