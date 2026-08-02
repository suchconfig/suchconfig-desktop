# Local Broker: Engineering the Invisible, Verifiable Credential Foundation for SuchConfig

> **Entitlement: Personal Pro (paid add-on)** — Free CE may show an upgrade teaser only; Broker inject runtime stays out of the public tree. Vision doc for Public Alpha — not a ship checklist. See [public-alpha-roadmap.md](../public-alpha-roadmap.md).

This is a powerful evolution of SuchConfig’s core promise. In the ever-expanding sea of complexity that makes up software development, SuchConfig already positions the Vault as the single source of truth for configurations, environment schemas, secrets (with placeholders), prompt templates, company guidelines, API specs, and security policies. Local Broker extends this foundation directly into the agent-to-API boundary—delivering a **local-first, CRDT-native credential broker** that eliminates plaintext leakage, configuration drift, and the dangerous broad filesystem grants that plague today’s agent setups.

Cloud and self-hosted agent vault proxies often inject credentials on egress via placeholders. Local Broker aims to be **native to SuchConfig’s architecture**: desktop control plane + local Broker runtime + Loro CRDT Vault—without requiring a SuchConfig-hosted vault database.

## Proposed Architecture: Local-First CRDT Broker in Rust + Tauri

### Core Principles (aligned with SuchConfig’s local-first mastery)

- **Everything stays local.** No cloud, no external sync required for core operation. CRDTs (Loro) ensure that Vault changes—whether from the Tauri UI, CLI, or concurrent agent edits—merge automatically and correctly, preserving every intent without conflict resolution or data loss.
- **Broker as a lightweight Rust service.** Ship it inside the planned **suchconfig-cli** binary family (or spawn via Tauri’s `tauri-plugin-process` / managed child process). Reuse the same Loro document that powers the SuchConfig Vault for zero-copy state sharing.
- **Library vs runtime.** Placeholder rules, scope schemas, and redaction live in **suchconfig-core** (`suchconfig_vault_core` + planned `suchconfig_broker_core`). IPC, injection, and daemon lifecycle live only in **suchconfig-cli** — never duplicated in Phoenix or Hex as a second implementation.
- **Secure IPC-first design.** Prefer Unix domain sockets (or Windows named pipes) over localhost HTTP for inter-process communication. This gives strong OS-level isolation without exposing ports. Fallback to localhost + mutual TLS (using self-signed CA generated on first run, pinned via Tauri’s secure storage) for cross-language agents.
- **No broad filesystem grants.** Agents never receive real secrets or broad `~/.config/` access. They receive scoped, short-lived “phantom” references (CRDT-backed opaque tokens) that only the Broker can resolve.
- **CLI-first parity.** Engineers who never open the desktop app can still run Local Broker from **suchconfig-cli** against a vault artifact (sidecar token, Trusted Folder, or encrypted archive). Desktop remains the rich control plane; CLI is a first-class, headless path.

### Key Components

#### 1. Vault Integration Layer (Loro CRDT-native)

The Broker loads a *view* of the SuchConfig Vault (filtered by agent scope, using Loro’s sub-document or map semantics). Secrets remain encrypted at rest (OS keychain + Argon2id master key). Placeholders in prompts/templates are resolved only at request time. Decode/merge math comes from **`suchconfig_vault_core`** in the suchconfig-core repo — the same crate the desktop NIF uses.

#### 2. Credential Injection Engine

**Primary mode: Explicit SDK calls** (recommended for safety). **suchconfig-cli** (and thin Rust/TypeScript SDK crates) expose:

```rust
// Example: suchconfig-cli / agent SDK
let broker = BrokerClient::new("/var/run/suchconfig-broker.sock");
let response = broker
    .call_api("https://api.stripe.com/v1/charges", &Request {
        method: "POST",
        headers: vec![("x-placeholder-key", "__stripe_sk__")],
        body: payload,
    })
    .await?;
```

The Broker resolves `__stripe_sk__` from the CRDT Vault, injects it, and strips it from logs/responses. Placeholder parsing and redaction helpers come from **`suchconfig_broker_core`** so desktop validation and CLI injection never diverge.

**Optional transparent proxy mode** (compatible with common HTTPS_PROXY agent setups, **opt-in only**). IPC and native tool bridges cover Broker-aware agents. Transparent proxy closes the gap for tools that already speak `HTTPS_PROXY` but were never written for SuchConfig: Cursor, Claude Code, Codex, curl, Python `requests`, Node fetch, and official provider SDKs.

```bash
# Explicit opt-in — never the default
suchconfig broker run --enable-proxy --scope my-app-staging -- claude-code
```

The child process only sees **dummy placeholders** in env (`__github_pat__`, `__stripe_sk__`, …). Outbound HTTPS routes through a loopback MITM (`hyper` + `rustls`); the Broker swaps placeholders for vault credentials on **scope allowlisted** hosts, then forwards. Secrets never land in agent env, shell history, or LLM context. A local CA is exported for child trust; desktop shows a clear warning when the toggle is on.

| Without 1.5 | With opt-in proxy |
| ----------- | ----------------- |
| Agent must call Broker tools / `api call` | Drop in `broker run --enable-proxy -- …` and existing HTTP clients work |
| Coding agents need custom wiring | One-command wrap + CA trust → staged API calls without pasting keys into `.env` |
| Proxy-style inject is familiar to agent-vault users | Same mental model, but **opt-in** and loopback-only — keeps local-first defaults |

This is the compatibility layer that makes “agents never hold plaintext secrets” true for everyday coding-agent and SDK stacks—without making MITM the happy path. Full behavior and security constraints: [local-broker-specs.md](./local-broker-specs.md) Flow D; delivery: [local-broker-roadmap.md](./local-broker-roadmap.md) slice **1.5**.

#### 3. suchconfig-cli (Broker + agent surface)

**suchconfig-cli** is the planned installable CLI (separate repo; may ship as `suchconfig` / `suchconfig-cli` with `broker` subcommands). It is the **runtime** for Local Broker — not a second copy of vault crypto. Desktop can spawn the same binary as a sidecar; CI and agent-only users install only the CLI.

```bash
# Start Broker (daemonized or foreground) — Pro license required
suchconfig broker start --vault default --scope openclaw-llm
suchconfig broker run --scope my-app-staging -- claude-code

# Explicit API call (recommended when the agent can call Broker)
suchconfig api call https://api.stripe.com/v1/charges \
  --placeholder __stripe_sk__ \
  --scope my-app-staging

# Opt-in transparent proxy (SDKs / coding agents that only know HTTPS_PROXY)
suchconfig broker run --enable-proxy --scope my-app-staging -- cursor-agent
```

**Headless modes (no Tauri required):**

| Mode | When to use |
| ---- | ----------- |
| **Sidecar** | Desktop already running; CLI connects to socket + session token from the app |
| **Archive / Trusted Folder** | Agent-only or CI: CLI loads a read-mostly vault view from encrypted export or synced folder |
| **Wrap agents (IPC / tools)** | `broker run` injects socket env; OpenClaw / Hermes / Ollama resolve via IPC or tool bridge — never see plaintext |
| **Wrap agents (proxy)** | Same wrap + `--enable-proxy` for Cursor / Claude Code / Codex / arbitrary HTTPS SDKs; dummy env only |

The CLI can wrap local LLMs (Ollama, OpenClaw, etc.) and inject a secure tool-calling interface so the LLM can request “context from SuchConfig Vault” without ever seeing secrets. Free-tier installs refuse `broker` subcommands with a clear upgrade path (same entitlement as desktop).

Naming note: product docs also use **suchconfig-agent** for the localhost gateway story; prefer one Rust binary family so Broker, `api call`, and agent wrappers share one release pipeline. See [local-broker-roadmap.md §3.1](./local-broker-roadmap.md#31-shared-library-vs-runtime).

#### 4. Local WiFi Sync & Multi-Device CRDT Convergence

Extend SuchConfig’s existing WiFi sync (already in your vision) to Broker state. A team member’s change to an API spec or secret placeholder propagates peer-to-peer and merges instantly on every machine running the Broker. Loro’s high-performance Rust implementation ensures sub-millisecond local edits and efficient delta syncs. CLI-started Brokers on paired machines consume the same converged CRDT view as desktop-spawned Brokers.

## Daily workflows: how Local Broker shows up in a real day

Architecture matters only if it removes friction on a Tuesday afternoon. These are the Phase 1 patterns engineers already dogfood (Session J / LB5–LB13 / LB9)—framed as benefits, not checklists.

### Morning: one Start Broker, then forget the socket

You open Project Vault for `my-app-staging`, click **Start Broker**, and desktop writes a Mode B scope manifest then spawns `suchconfig-cli`. From that point the CLI, scripts, and agents all talk to the same Unix socket. You never paste a Stripe or GitHub token into a terminal history, a teammate’s chat, or an LLM prompt—only placeholders like `__stripe_sk__` or `__HTTPBIN_TOKEN__`.

**Benefit:** Secrets stay in the vault; the broker is the only process that decrypts them for egress. Status in the UI matches `suchconfig broker status` so you trust what is running before you ship a change.

### Least privilege on linked `.env` files

A staging `.env` often mixes harmless flags (`DEV_MODE`, `PHOENIX_PORT`) with tokens. Per-key Broker toggles let you enable only `HTTPBIN_TOKEN` / `STRIPE_SECRET_KEY` for the broker while leaving ports and paths out of the scope manifest. Disable a key → Stop/Start → that placeholder disappears from the allowlist and `api call` returns `unknown_placeholder`.

**Benefit:** Agents and scripts cannot “accidentally” resolve credentials you never meant to expose to the broker—even when they live in the same dotenv as local tooling.

### Host rules instead of memorizing placeholders

You add a service rule once: name `stripe`, host `api.stripe.com`, placeholder `__stripe_sk__`, inject as `bearer`. Later, `suchconfig api call https://api.stripe.com/v1/charges --scope my-app-staging` (no `--placeholder`) resolves via the host. `broker discover` returns service names and placeholder **names** for agents and docs—never secret values. A wrong placeholder on that host fails closed with `placeholder_mismatch`.

**Benefit:** Day-to-day calls match how humans think (“call Stripe”) instead of hunting which `__…__` string belongs to which API. Misconfiguration fails loudly instead of sending the wrong key.

### Local agents that never see plaintext

OpenClaw or Ollama under `broker run --no-inject-env` only receive tool bridges (`get_context` / `call_api`). Context lists placeholders and service metadata; egress injects inside the broker and returns redacted bodies (`Bearer [REDACTED]`). Hermes-style wrappers that need env substitution still go through `broker run`, with audit rows for every resolution.

**Benefit:** You can let a local LLM “use the vault” to hit staging APIs without teaching it your secrets—and without dumping tokens into child process env for tool-bridge paths.

### Coding agents that already speak HTTPS_PROXY

When Cursor, Claude Code, Codex, or a stock SDK cannot call Broker IPC, you opt into transparent proxy from the Local Broker modal (or `--enable-proxy`). The child gets dummy env (`__github_pat__=__github_pat__`), `HTTPS_PROXY` to loopback, and a local CA for trust. Allowlisted hosts inject; `example.com` (or any off-list host) gets CONNECT `403`. Proxy refuses to start without a non-empty domain allowlist **and** at least one service rule—so you cannot “turn on MITM with an open world.”

**Benefit:** Same “agents never hold plaintext” guarantee for tools you did not write—without making MITM the default happy path, and without pasting production keys into project `.env` for the agent to read.

### What changes for users coming from proxy-style agent vaults

You keep the mental model (placeholders in, secrets at the edge) but gain CRDT project vault, desktop Mode B handoff, per-key `.env` control, `broker discover`, native tool bridges, and an **opt-in** loopback proxy instead of MITM-as-default. Onboarding is “enable credentials → Start Broker → wrap or `api call`,” not “deploy a separate proxy machine.”

## Innovative Features That Set SuchConfig Apart

- **Verifiable Agent Identity & Least-Privilege Scopes.** Use OS process attestation (macOS `codesign`, Linux `systemd` dynamic users, Windows AppLocker) + CRDT-stored agent manifests. An agent can only access Vault entries explicitly allowed by its scope. No more “give the LLM full ~/.env access.” Per-key `.env` Broker toggles make that least privilege practical on real project files.
- **CRDT-Backed Dynamic Policies.** Store API specs, rate-limit rules, and prompt templates in the same Loro document. Broker can auto-validate requests against OpenAPI schemas parsed locally (leveraging your data-parser expertise) and reject drift before it happens. Service rules already encode host → placeholder → inject-as for everyday egress.
- **Zero-Knowledge Local LLM Integration.** For Ollama/OpenClaw: The Broker exposes a secure “context tool” endpoint. The LLM receives redacted context + placeholder references. Only the Broker injects real values on outbound calls (`broker run --no-inject-env`). This closes the prompt-injection → secret-leak vector completely.
- **Opt-in Transparent Proxy for Everyday Tools.** IPC-first by default; power users enable a loopback MITM so coding agents and stock SDKs get Agent Vault–style placeholder injection without rewriting their HTTP stack—or pasting production keys into project `.env` files. Requires allowlist + `services[]` before start.
- **Audit & Tamper-Proof Logging.** All resolutions logged as CRDT operations (Loro’s OpLog). Replayable, mergeable across devices, and exportable as encrypted archives for compliance—without ever storing plaintext. Desktop `api call` / proxy paths already surface `audit.outcome` and `service_name` when a host rule matched.
- **Embedded/IoT Extension (Nerves-ready).** For edge devices, the same Broker binary compiles to Nerves targets. A device can join the WiFi mesh, pull scoped credentials via CRDT, and broker calls to cloud APIs—all without exposing keys to the application layer.
- **Tauri UX Polish.** The desktop app shows a live “Broker Status” panel (LiveView-inspired reactivity via Tauri events): connected agents, active sessions, recent resolutions, optional proxy URL + CA export. **View Broker Connections** opens a per–vault-item map of how Secrets, Placeholders, Schemas, Policies, and `.env` keys flow through the Local Broker Runtime to External Agents / LLMs. One-click “Isolate Agent Sandbox” that spins up a micro-VM (via `firecracker` or Tauri’s sandbox APIs) with Broker as the sole egress point.

## Implementation Roadmap (Pragmatic & High-Velocity)

1. **Phase 0 (MVP):** `suchconfig_broker_core` in suchconfig-core + Rust Broker runtime in suchconfig-cli (Unix socket + explicit SDK). Desktop Project Vault panel + license gate. Ship as `suchconfig broker`.
2. **Phase 1:** Transparent proxy fallback + Ollama/OpenClaw wrapper; `.env` / project credential enablement; CLI-only vault load paths.
3. **Phase 2:** WiFi P2P CRDT sync for Broker state + agent attestation.
4. **Phase 3:** Nerves/IoT support + advanced parsers for auto-generating scopes from API specs.

Canonical delivery detail: [local-broker-roadmap.md](./local-broker-roadmap.md). Shared library vs runtime: [§3.1](./local-broker-roadmap.md#31-shared-library-vs-runtime).

This design turns the Broker into the strategic advantage you described: Loro gives us the velocity and polish to ship a delightful, Anytype-level experience for secrets *today*. Local WiFi sync makes SuchConfig the invisible foundation engineers need. Such configuration requires such a tool—**SuchConfig**.


