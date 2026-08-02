# Data sovereignty in SuchConfig

**Data sovereignty** here means: **you** decide where vault data lives, **who** can read it, and **how** it moves between machines. SuchConfig does not require a hosted vault to obtain merge-safe configs, secrets, and policies—the product is built so **local operation is complete**, and anything that leaves the device is **explicit**, **encryptable**, and **under your keys**.

This document aligns **product positioning** with the engineering boundaries described in [Local-first strategy](../local-first/local-first.md) and [CRDT via Loro](../local-first/CRDT-via-Loro.md).

SuchConfig’s **shipping** persistence model is **SQLite + encrypted Loro snapshots** unless an ADR changes it ([handoffs](#handoffs-and-backups-sovereign-transport) below).

---

## One surface, one principle

| Surface | Primary store | Sovereignty takeaway |
| ------- | ------------- | --------------------- |
| **Project Vault + Secrets Vault** | **SQLite** as authoritative; **encrypted Loro snapshots** per vault item in Rust (`VaultItemDoc`) | Vault **load, save, merge, and index** do not use SuchConfig’s network for vault bytes; handoffs are **password-protected archives**, **Trusted Folder**, and optional **LAN P2P**—not a mandatory sync vendor. |

**Default sovereignty is “on this machine,”** not “in our cloud.”

---

## What Project Vault adds (Loro + encryption)

Project Vault is the place for **environment schemas, secrets (with placeholders where product requires), prompts, guidelines, API specs, and security policies**.

- **CRDT choice** — Vault items use **[Loro](https://loro.dev/)** in **Rust** (`suchconfig_vault_core`) so merge math shares the same **trust boundary** as encryption and archive packing. Rationale and messaging live in [CRDT via Loro](../local-first/CRDT-via-Loro.md); wire format and APIs in [Loro-backed CRDT (developer reference)](../local-first/project-vault-CRDT-usage.md).
- **No hosted merge** — “CRDT-synced” in copy means **merge-capable on device**, not “SuchConfig runs a sync service for your vault.” Merges run **after** you bring copies together (import, Trusted Folder, LAN Handoff), without uploading vault content for coordination.
- **Encryption at rest** — Persisted items are **opaque encrypted blobs** in SQLite; plaintext exists only **transiently** during edit/decode inside the app boundary, using the same **`EnvCrypto`** family as secure notes ([developer reference](../local-first/project-vault-CRDT-usage.md)).
- **Causality without exposure** — The oplog supports **deterministic merges** and future **time-travel** UX; it does **not** replace redaction, passkeys, or audit discipline for secrets. See [Tracking causality](./tracking-causality.md), especially the section on sensitive data.

---

## Handoffs and backups (sovereign transport)

Sovereignty is not “no sharing”—it is **your choice of transport** and **your keys**.

- **Encrypted archives** — **`.suchvault`** (and related flows) are the **primary** team handoff story: export locally, move the file however you already move sensitive files, import locally. Merge semantics are defined by **Loro** + `ProjectVault` rules, not by a third-party document host.
- **Trusted Folder** — Encrypted snapshots to a folder you own (iCloud / Dropbox / NAS / USB); SuchConfig does not operate that sync plane.
- **LAN Wi‑Fi P2P** — Opt-in pairing between devices you control; maturity notes live in [public-alpha-roadmap.md](../public-alpha-roadmap.md) and [P2P security](../security/p2p-wifi-sync-security.md).
- **Deltas when appropriate** — Loro can export **updates since a peer version vector** so future envelopes can stay smaller when both sides already share history—still **end-to-end under vault passwords** where the product requires it.
- **Backups** — Users retain **device backups** and **explicit vault exports**. SuchConfig does not need to **store** your vault in its infrastructure; **you** operate backup hygiene.
- **On-device import** — Planned Free path to migrate from other managers **on your machine** (formats as they ship); not in Public Alpha.

---

## Trust, transparency, and honest limits

- **Structural audit** — merge audit events and CRDT merge summaries aim to record **what class of operation** ran and **fingerprints**, not secret payloads.
- **Export integrity (lite)** — encrypted archives, merge audit, optional vault-derived envelope signing / manifest hashes. W3C DID / Verifiable Credentials are **out of initial open-core vision**.
- **Open-core and verifiable builds** — Free CE vault/crypto source is inspectable; sovereignty claims should still be backed by **your** threat model review.
- **Limits** — CRDTs give **strong eventual consistency** for replicated **document state**; they do not solve **compliance certification** by themselves, **off-device key loss**, or **malware on the device**. [CRDT via Loro](../local-first/CRDT-via-Loro.md) stays explicit about tradeoffs.

---

## Messaging that matches the implementation

Safe external phrases (from [CRDT via Loro](../local-first/CRDT-via-Loro.md)):

- “**Your vault stays on this device** until you export.”
- “**Local-only · CRDT-synced**” — merge-capable, **not** cloud-synced; tooltips should say so.
- “**No SuchConfig server** required for vault load, save, merge, or index.”

Avoid implying **Automerge**, **always-on collaborative servers**, or **plain CRDT files on disk** as the shipped vault layout unless the repo actually moves to that model—the **authoritative** desktop vault today is **SQLite + encrypted Loro blobs** wired through **`ProjectVault`**.

---

## Related documents

- [Local-first strategy](../local-first/local-first.md)
- [CRDT via Loro](../local-first/CRDT-via-Loro.md)
- [Trusted Folder sync](../features/trusted-folder-sync.md)
- [P2P security](../security/p2p-wifi-sync-security.md)
- [Public Alpha roadmap](../public-alpha-roadmap.md)
