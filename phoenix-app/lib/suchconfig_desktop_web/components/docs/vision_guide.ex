defmodule SuchConfigDesktopWeb.Components.Docs.VisionGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Vision</div>
        <h1>Why SuchConfig exists</h1>
        <p class="docs-lede">
          SuchConfig is built for developers who need one trusted, local-first place for sensitive project work — passwords, configs, secrets, and the tools that support secure day-to-day engineering.
        </p>
      </header>

      <section class="docs-section">
        <h2>One app, one source of truth</h2>
        <p class="docs-prose">
          Modern development scatters credentials across password managers, <code>.env</code>
          files, notes apps, and chat history. SuchConfig brings that material together in a vault you control on your own machine:
        </p>
        <ul class="docs-list">
          <li>
            <strong>Project Vault</strong>
            — project folders, secure notes, configs, prompts, and encrypted archives
          </li>
          <li><strong>Secrets Vault</strong> — logins, API keys, SSH material, and secure notes</li>
          <li>
            <strong>Developer tools</strong>
            — like the local Generator for passwords, passphrases, and usernames
          </li>
          <li>
            <strong>Sync on your terms</strong>
            — Trusted Folder backups and WiFi P2P between your devices, not a vendor vault cloud
          </li>
        </ul>
        <p class="docs-prose muted">
          The goal is simple: replace the daily friction of jumping between Bitwarden, scattered env files, and ad hoc notes with a single app designed for how engineers actually work.
        </p>
      </section>

      <section class="docs-section">
        <h2>Data sovereignty & security</h2>
        <p class="docs-prose">
          Your most sensitive material should not depend on a third-party database that could be breached, subpoenaed, or misconfigured. SuchConfig stores vault data <strong>on your device</strong>, encrypted at rest, with unlock controlled by your passkey or master key.
        </p>
        <div class="docs-callout">
          <.icon name="key" size={16} />
          <div>
            <strong>Non-negotiable:</strong>
            no SuchConfig-hosted vault sync server, no telemetry of secret bodies, and explicit warnings before anything leaves the machine via export or backup you configure.
          </div>
        </div>
        <ul class="docs-list pt-4">
          <li>Encrypted CRDT snapshots in SQLite — merge-safe history without a central authority</li>
          <li>Trusted Folder and archives you place in storage <em>you</em> own</li>
          <li>Local-only generation for passwords — nothing routed through a hosted generator</li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Local-first as a core value</h2>
        <p class="docs-prose">
          Local-first means the app is fully useful offline. Network is optional acceleration — backup, LAN sync, updates — not a requirement to read or edit your vault.
        </p>
        <ul class="docs-list">
          <li>
            <strong>Works offline</strong> — travel, air-gapped clients, or locked-down networks
          </li>
          <li>
            <strong>CRDT merges</strong>
            — concurrent edits converge without manual conflict resolution when you sync or share archives
          </li>
          <li>
            <strong>You choose transport</strong>
            — iCloud, Dropbox, USB, encrypted handoff, or direct WiFi between paired desktops
          </li>
          <li>
            <strong>No lock-in to our cloud</strong> — because there isn’t one for your vault data
          </li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Built for AI-augmented workflows</h2>
        <p class="docs-prose">
          AI coding tools, agents, and CI pipelines need context — but they should not receive raw secrets from leaky
          <code>.env</code>
          files, pasted chat logs, or repo commits. SuchConfig is designed to sit between your real credentials and the tools that consume configuration:
        </p>
        <ul class="docs-list">
          <li>
            Keep <strong>environment schemas and secrets</strong>
            in the vault instead of fragile copies on disk
          </li>
          <li>
            Use <strong>placeholders</strong>
            and structured config profiles so agents and exporters reference names, not plaintext
          </li>
          <li>
            Protect <strong>sensitive project files</strong>
            — rules, API specs, security policies — alongside credentials in one merge-safe store
          </li>
          <li>
            Path toward <strong>localhost agents</strong>
            (e.g. OpenClaw, <code>suchconfig-agent</code>) that resolve secrets without exposing them to the public internet
          </li>
        </ul>
        <p class="docs-prose muted">
          The north star: ship AI-assisted development without normalizing “just paste your .env into the chat.”
        </p>
      </section>

      <section class="docs-section">
        <h2>What we’re building toward</h2>
        <p class="docs-prose">
          SuchConfig is the foundation. Shipped today: CRDT-backed vaults, Trusted Folder backup, device pairing for LAN sync, JWT analysis, and the local Generator. On the roadmap: richer Secrets Hub resolution in editors, context export packs, security auditing, and more local-first utilities — always processed on your device.
        </p>
        <table class="docs-table">
          <thead>
            <tr>
              <th>Today</th>
              <th>Direction</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Project & Secrets vaults</td>
              <td>Unified project brain + credential manager replacement</td>
            </tr>
            <tr>
              <td>Trusted Folder & pairing</td>
              <td>Live LAN sync, recovery kits, team handoff archives</td>
            </tr>
            <tr>
              <td>Generator & analyzers</td>
              <td>More dev utilities (formatters, env validation, CI wizards)</td>
            </tr>
            <tr>
              <td>Local CRDT merge</td>
              <td>Graph views, context exporter, agent integrations</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="docs-section">
        <h2>Explore the guides</h2>
        <p class="docs-prose">
          This vision shows up in the product docs below — start with
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="secrets-vault"
          >
            Secrets Vault
          </button>
          or
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="project-vault"
          >
            Project Vault
          </button>
          for day-to-day use, or
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="trusted-folder"
          >
            Trusted Folder
          </button>
          to back everything up.
        </p>
      </section>
    </article>
    """
  end
end
