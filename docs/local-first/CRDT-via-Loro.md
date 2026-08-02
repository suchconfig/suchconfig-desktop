# CRDT via Loro

This note is the **canonical wording** for translating Project Vault’s **Loro-backed** CRDT work into **help docs**, **in-product copy**, and **marketing**. Product scope and privacy: [Local-first strategy](./local-first.md) · [Data sovereignty](../concepts/data-sovereignty.md).

---

## CRDT fundamentals (for FAQs and education pages)

These basics align with common explainers (for example general overviews of conflict-free replicated data types). They are **not** SuchConfig-specific; use them when a reader asks *what a CRDT is* before *why SuchConfig uses one*.

**What the letters mean**

- **Conflict-free** — The data structure is designed so independent edits can be **merged automatically** instead of stopping the user with a classic “merge conflict” file for every clash.
- **Replicated** — The **same logical document** can exist in more than one place (two machines, two exports, an archive and a local copy). Each copy can receive updates.
- **Data type** — CRDTs are not one generic blob; they are **specific structures** (text, maps, counters, sets, graphs, …) with rules that make automatic merging well-defined.

**How they behave (plain language)**

- **Local first** — You can edit **now** without waiting for a server round-trip. Other copies catch up when you **exchange** data (file, archive, future sync channel).
- **Eventual consistency** — After all edits are shared and merged, replicas **converge** to a common result. Right after an edit, two copies may briefly differ; that is normal.
- **Order often does not change the final merged result** — For well-designed CRDTs, merging the same set of changes in different orders still lands on the **same** end state (mathematically). That is what makes offline and “send files later” workflows tractable.

**Common families** (vocabulary for technical readers)

| Kind of data | Typical CRDT style | Intuition |
| ------------ | ------------------ | --------- |
| Text | Sequence / text CRDT | Concurrent typing and deletes combine like collaborative editors. |
| Key–value / metadata | Map CRDT | Fields update independently; parallel edits to different keys compose cleanly. |
| Counters, sets, graphs | Specialized CRDTs | Used in databases, games, social graphs—less visible in vault prose, but the same ideas apply. |

SuchConfig’s vault document model uses **text plus maps** (see the developer reference for Loro container names). We do **not** claim every mathematical property of every CRDT family—only what our **concrete implementation** is built for.

**Tradeoffs (stay honest in marketing)**

- **Not “strong consistency” in the database sense** — Everyone does not see the same bytes at the same instant; **eventual** convergence is the goal after merges.
- **History and size** — CRDTs can retain **causal history** to merge correctly; storage and snapshots can **grow** unless the system **compacts** or prunes (product decisions, not magic).
- **Not every edit is pleasant** — Concurrent edits to the **same sentence** still resolve, but **human intent** (which wording you prefer) may require normal editing after merge. CRDTs remove a class of **mechanical** conflicts, not all product design questions.

**Optional third-party overview**

For a longer standalone introduction in the same spirit as the above, see: [What is a CRDT? (Data Driven Daily)](https://datadrivendaily.com/what-is-a-crdt-conflict-free-replicated-data-type/). SuchConfig does not control that site; link it as **general background**, not as a specification of our product.

---

## Why Loro for SuchConfig (especially Project Vault)

SuchConfig uses **Loro** as the concrete CRDT engine behind **Project Vault** items and **encrypted archive** merge paths—not as a hosted sync product, but so **document and file handoffs** on your machine converge predictably. The points below are the product-facing reading of the same tradeoffs captured in the roadmap; they are safe to reuse in FAQs and sales conversations.

**Where merging runs**

- Vault **load, save, merge, and archive pack/unpack** are intentionally handled in **Rust** next to encryption and validation, with Phoenix/LiveView orchestrating—not re-implemented separately in Elixir or in the browser for vault bytes.
- That keeps **one codec and one merge story** for SQLite-backed items, **`.suchvault` / archive** import, and future **Tauri** surfaces, instead of two stacks that must stay byte-identical forever.

**Why Loro over “any CRDT” or a JS-first stack**

- **Rust-first API** — Loro ships as a **Rust crate** with a first-class Rust API. The Yjs ecosystem (including **Yrs** in Rust) is excellent, but Yjs itself is **JavaScript-first**; for SuchConfig the **trust boundary** for vault math lives in Rust, so a Rust-primary engine reduces impedance and avoids making the browser or Wasm layer the source of truth for vault merges.
- **One document, many shapes** — A single logical vault item can carry **editable text**, **structured metadata (maps)**, and—over time—**links and graph-friendly lists/trees** for guidelines, specs, and policies. Loro models that in **one document** without bolting together unrelated doc types.
- **Handoffs and audits** — **Full snapshots** and **deltas vs another peer** map cleanly to **archive envelopes** and to **merge summaries** and local **audit rows** (for example `crdt_merge` style events), so support and security teams can explain *what happened* after an import without claiming cloud sync.
- **History without a second product** — Built-in **version vectors, checkout, revert, and fork** align with a future **time-travel** and revision story **inside** the vault product, not as a separate dependency users must reason about.

**What we did not optimize for**

- **Interoperating with arbitrary Yjs providers** out of the box—that is a different product shape (always-on collaborative editing through a vendor’s sync plane). SuchConfig optimizes for **local-first, explicit export/import**, with Loro as the on-device merge engine.
- **Running the vault codec only in Elixir** — fine for ephemeral server-only state elsewhere, but a poor fit for **encrypted blobs**, desktop packaging, and a single archive format shared across runtimes.

**Honesty and escape hatches**

- We track **binary size** (desktop artifacts) and may add CI gates as the stack grows.
- The Rust boundary is intentionally **narrow** (encode/decode/apply updates/diff); if the ecosystem shifts, **re-evaluating another Rust CRDT** is a contained engineering change, not a rewrite of the whole vault.

---

## In one sentence

**SuchConfig uses CRDT-backed documents so your vault can merge changes from parallel work—without a sync server—while staying local-first and offline-friendly.**

---

## “CRDT compliance”—what we mean (and what we don’t)

**We do not mean** regulatory compliance (GDPR, SOC 2, etc.). Those are separate topics.

**We do mean** the product is built on **conflict-free replicated data types (CRDTs)**: a family of algorithms that let copies of the same document be edited in different places or at different times and then **merged automatically** into a **consistent result**, without a central database deciding who wins.

Marketing-safe phrasing:

- “**CRDT-backed merging**” or “**automatic, intent-preserving merges**”
- Avoid leading with “CRDT” in headlines unless the audience is technical; lead with the **outcome** (fewer conflicts, safer handoffs, works offline).

---

## The benefit in simple terms

| User problem | Without CRDT-style merging | With CRDT-style merging (our direction) |
| ------------ | ------------------------- | ---------------------------------------- |
| Two people change the same note or you edit on two machines | Easy to **overwrite** work, or end up in **manual conflict** hell | Edits are **combined** where possible; fewer “pick mine or theirs” moments |
| You share work via **files** or **archives** instead of a cloud drive | Hard to know how to **merge** two versions fairly | Merges follow **mathematical rules** so outcomes are **predictable** and **reproducible** |
| You want **privacy** and **no cloud** | Traditional “sync” products want **servers** | Merging can happen **on your machine**; **no SuchConfig server** holds your vault content for sync |

**Bottom line for positioning:** SuchConfig is aiming for **serious team and solo workflows** where configuration, prompts, and policies matter, but **you don’t want** your knowledge base **held hostage** by a hosted sync layer to get **safe merges**.

---

## Why this fits SuchConfig’s audience

SuchConfig’s buyers and users tend to care about:

- **Developers and platform teams** — env schemas, API specs, prompts, guidelines; parallel edits and handoffs are normal.
- **Security- and privacy-conscious teams** — “local-only” and **no background upload of vault content** are differentiators.
- **Air-gapped or policy-heavy environments** — **encrypted archives** and **offline** use are realistic; CRDTs help **merge** those handoffs **without** requiring a shared SaaS database.

CRDT support supports a credible story: **local-first does not have to mean “last save wins” or manual diffing** for every collaboration pattern.

---

## “Local-only” and “CRDT-synced” together

Recommended explanations:

- **Local-only:** Vault content **is not synced by SuchConfig through our cloud**. What you see is **stored on this device** unless **you** export or copy it elsewhere.
- **CRDT-synced:** The app uses **CRDT machinery** so copies of a document can be **reconciled** when you bring them together (for example after importing an archive or merging branches of work). **“Synced” here means “merge-capable,” not “cloud-synced.”**

Short badge copy (matches in-app direction):

- **“Local-only · CRDT-synced”** — fine for users who want a hint of depth; tooltip or docs should clarify **no cloud sync**.

Tooltip / footnote example:

- “Vault items can be merged using CRDTs on this device. SuchConfig does not upload your vault to our servers for synchronization.”

---

## What to promise externally (honesty ladder)

Use language that matches **shipping** behavior:

1. **Today (infrastructure / engine):** SuchConfig is **investing in a Loro-backed Rust core** and optional in-process merge capabilities so **future** vault items and handoffs can use **automatic merges** offline.
2. **Near-term product wins (as they ship):** Encrypted **archive import/export** with **merge summaries**, fewer destructive overwrites, clearer **audit** of what changed.
3. **Longer-term:** Richer **VaultItem** editing, **archive formats** carrying CRDT snapshots/deltas, **graph** and **time-travel** UX—still **without** requiring hosted vault sync.

Avoid claiming “every note is already CRDT-merged end-to-end” until the UI and archive pipeline fully use **`vault_items`** and CRDT merge paths everywhere. When in doubt, say **“rolling out”** or **“introducing CRDT-backed merging for…”** with a specific scope.

---

## Competitor contrast (high level, not naming names)

| Approach | Message |
| -------- | ------- |
| Cloud note / wiki with live sync | Convenient, but **your content** and **merge policy** depend on **their** service. |
| Git-only | Powerful, but **merge conflicts** are familiar; not everyone wants **Git** for prose and prompts. |
| Last-write-wins local tools | Simple, but **easy to lose edits** when two people work in parallel. |
| SuchConfig direction | **Local-first**, **offline**, **CRDT-backed merging** for vault items—**you** control export; **no** SuchConfig-hosted vault sync required for merge math. |

---

## Copy bank (adapt freely)

**Elevator (non-technical):**

- “SuchConfig’s vault is built to **merge parallel changes** safely **on your machine**, so teams can hand off work **without** sending everything through **our** cloud.”

**Elevator (technical):**

- “Project Vault uses **Loro CRDTs** in Rust for **offline-first**, **mergeable** documents—archives and local storage, not a sync service.”

**Feature bullet (website):**

- **Conflict-friendly editing** — CRDT-backed items so parallel edits and archive handoffs **merge predictably** without a sync server.

**Trust bullet:**

- **Your vault stays yours** — **No SuchConfig cloud** required for vault load, save, merge, or index; network use stays in your control.

**FAQ-style:**

- **“Do I need the internet for CRDT merging?”** No. Merging runs **locally**. Network is unrelated to vault CRDT operations.
- **“Is this the same as Google Docs sync?”** No. Docs-style products use **servers**. SuchConfig focuses on **local** state and **explicit** export/import when you share.

---

## Related documents

- [Local-first strategy](./local-first.md)
- [Data sovereignty](../concepts/data-sovereignty.md)
- [Public Alpha roadmap](../public-alpha-roadmap.md)
