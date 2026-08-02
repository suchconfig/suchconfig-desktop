defmodule SuchConfigDesktopWeb.Components.Docs.ProjectVaultGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Vaults</div>
        <h1>Project Vault</h1>
        <p class="docs-lede">
          Your local project brain — configs, env schemas, prompt templates, guidelines, and secure notes organized by project. Everything stays on your device until you choose to export or back up.
        </p>
      </header>

      <section class="docs-section">
        <h2>What it is</h2>
        <p class="docs-prose">
          Project Vault holds <strong>project folders</strong>. Each folder is a workspace for notes and files tied to one app, client, or codebase. Edits merge safely over time using CRDT history — no manual conflict resolution for normal saves.
        </p>
        <div class="docs-callout">
          <.icon name="vault" size={16} />
          <div>
            <strong>Local-first:</strong>
            vault data is not uploaded to a cloud service. Network use is limited to app updates and license checks — not your notes.
          </div>
        </div>
      </section>

      <section class="docs-section">
        <h2>Get started</h2>
        <ol class="docs-steps">
          <li>Open <strong>Projects</strong> from the rail.</li>
          <li>
            Click <strong>New project</strong> and name your folder (e.g. <code>my-saas-app</code>).
          </li>
          <li>Click <strong>Open</strong> on the project card to enter Project Vault.</li>
          <li>
            Create notes, import files, or link a folder on disk if you use linked-project sync.
          </li>
        </ol>
        <p class="docs-prose muted">
          Unlock your vault first if prompted — the global passkey protects encrypted content at rest.
        </p>
      </section>

      <section class="docs-section">
        <h2>Inside a project</h2>
        <ul class="docs-list">
          <li>
            <strong>Secure notes</strong>
            — markdown-friendly items for env snippets, prompts, runbooks, and specs
          </li>
          <li>
            <strong>Import</strong>
            — bring local files in as vault items when linking or importing a project tree
          </li>
          <li>
            <strong>Secure Archive</strong>
            — export an encrypted <code>.suchvault</code>
            bundle for handoff or air-gapped backup
          </li>
          <li>
            <strong>Activity</strong> — from Projects, open Activity to review recent vault changes
          </li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Sharing and backup</h2>
        <p class="docs-prose">
          Project Vault does not sync by itself to the cloud. To move data between machines:
        </p>
        <ul class="docs-list">
          <li>
            <strong>Trusted Folder</strong>
            — automatic encrypted backups to your iCloud/Dropbox/NAS (includes project items)
          </li>
          <li>
            <strong>Secure Archive</strong> — one-off encrypted export you can email or copy manually
          </li>
          <li>
            <strong>WiFi P2P sync</strong>
            — live LAN sync between paired desktops (pairing available today; live deltas shipping next)
          </li>
        </ul>
        <p class="docs-prose">
          See the
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="trusted-folder"
          >
            Trusted Folder
          </button>
          and
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="wifi-p2p-sync"
          >
            WiFi P2P sync
          </button>
          guides.
        </p>
      </section>

      <section class="docs-section">
        <h2>Tips</h2>
        <ul class="docs-list">
          <li>One project folder per repo or product keeps exports and backups focused.</li>
          <li>
            Use tags and titles consistently — Trusted Folder matches items by folder + title on import.
          </li>
          <li>
            Before sharing an archive, confirm recipients understand it contains sensitive project material.
          </li>
        </ul>
      </section>
    </article>
    """
  end
end
