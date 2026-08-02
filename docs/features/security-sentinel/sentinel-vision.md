# Security Sentinel Vision

> **Entitlement: Personal Pro (paid add-on)** — bundled with Local Broker for Public Alpha. Free CE may show an upgrade teaser only; scan engines stay out of the public open-core tree. See [public-alpha-roadmap.md](../../public-alpha-roadmap.md).

The local-first security layer that turns supply chain chaos into calm, actionable control.

## The Problem

Supply chain attacks are no longer rare events — they are a daily reality. The latest Miasma npm worm compromised 57 packages with 286 malicious versions in under two hours, using novel evasion techniques and injecting persistent backdoors into AI coding assistant configurations (`.claude/`, `.cursor/`, `.gemini/`, `.vscode/`). These attacks don’t just steal credentials — they poison the tools developers trust most.

Traditional scanners and cloud-based tools are helpful but fundamentally reactive, network-dependent, and blind to the local development surface where these attacks now strike hardest. Teams are left with alerts, fatigue, and fragmented tools.

## The SuchConfig Solution

Supply Chain Sentinel is the proactive, local-first security foundation built into SuchConfig from day one. It continuously analyzes the projects in your Project Vault, detects real threats (including today’s Miasma-class attacks), explains them clearly, and helps you take action — all without ever sending your code or lockfiles to the cloud.

It combines deep structural parsing, CRDT-powered history and team collaboration, and direct integration with Local Broker so findings don’t just inform — they enforce safer behavior going forward.

## Key Capabilities

- **Deep, Parser-Driven Detection** — Purpose-built parsers for `package.json`, lockfiles (npm/yarn/pnpm), `binding.gyp`, GitHub workflows, and the exact AI coding assistant configuration paths attackers are now targeting. Detects malicious package versions, typosquatting, execution triggers, and injected backdoors.
- **Explainable Risk Scoring** — Every finding comes with clear, human-readable reasoning and severity. Understand why something is risky — not just that it is.
- **CRDT-Powered Security Manifests** — Scan results, allow/deny lists, annotations, and resolutions live in Loro CRDT documents. Changes merge automatically across your devices and team. Full tamper-proof history travels with the project.
- **Local Broker as the Action Layer** — High-risk findings automatically generate proposed Broker policies (scoped restrictions, extra logging, approval gates). Turn detection into enforceable, least-privilege guardrails with one click.
- **Delightful, Educational Experience** — A calm, Anytype-level interface in the Tauri desktop app that makes complex supply chain defense feel manageable and empowering. One-click quarantine, manifest updates, and policy proposals.
- **True Local-First Execution** — Runs entirely on your machine or trusted local network. Works offline. Optional signed allow/deny lists sync via Trusted Folder or WiFi P2P. No data leaves your control.

## How It Works

1. Add a project to your Project Vault.
2. Sentinel automatically (or on-demand) scans package manifests, lockfiles, AI config directories, and execution triggers.
3. Findings appear in a clear, prioritized view with explanations and recommended actions.
4. One-click actions update your CRDT security manifest, add items to allow/deny lists, or propose scoped Local Broker policies.
5. Changes converge instantly across your team via WiFi P2P or Trusted Folder.

## Why Supply Chain Sentinel Is Different

Most security tools treat supply chain defense as an external service. Sentinel treats it as a core, living property of your projects — stored in CRDTs, enforceable through Local Broker, and fully under your control.

- No cloud upload of source or lockfiles
- Automatic team-wide convergence without manual sync
- Findings become policy, not just alerts
- Works in air-gapped and high-security environments
- Built for the exact attack patterns dominating the news today (and tomorrow)

## Who It’s For

- Individual developers who want to stop worrying about the next npm worm
- Teams that need collaborative, mergeable security posture without central servers
- Organizations adopting local-first or zero-trust workflows
- Anyone building with AI coding assistants who wants to protect against config poisoning

## How It Fits Into SuchConfig

Supply Chain Sentinel is one of the four foundational pillars of SuchConfig at launch:

- **Project Vault** — Organize and version your projects with CRDTs
- **Secrets Vault** — Single source of truth for secrets with placeholders and scopes
- **Local Broker** — Verifiable credential injection for agents and tools
- **Supply Chain Sentinel** — Proactive, local-first defense that turns findings into guardrails

Together they form a cohesive, delightful system that helps engineers manage the ever-growing complexity of modern software development with security, efficiency, and joy.

SuchConfig is the invisible foundation engineers need in the ever-expanding sea of complexity. Such configuration requires such a tool — SuchConfig.

---

## Optional follow-ups

This copy is modular — sections can be lifted onto the site, landing page, or feature comparison page.

Possible next pieces:

- A shorter hero version for the homepage
- Comparison language vs traditional tools (Socket, Dependabot, etc.)
- A visual diagram (Mermaid or image prompt)
- Testimonial-style quotes or use-case cards
