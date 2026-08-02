defmodule SuchConfigDesktopWeb.Components.Docs.SecretsVaultGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Vaults</div>
        <h1>Secrets Vault</h1>
        <p class="docs-lede">
          A local-first password manager inside SuchConfig — logins, API keys, SSH keys, and secure notes encrypted on your device. No vendor vault server in the middle.
        </p>
      </header>

      <section class="docs-section">
        <h2>What it is</h2>
        <p class="docs-prose">
          Secrets Vault is separate from Project Vault but uses the same encryption and CRDT foundation. Credentials live in encrypted storage and only decrypt while your vault is <strong>unlocked</strong>.
        </p>
        <div class="docs-callout">
          <.icon name="key" size={16} />
          <div>
            <strong>Unlike typical cloud password managers,</strong>
            your secrets are not copied through 1Password, LastPass, or Bitwarden servers — they stay on your machine unless you back up or export them yourself.
          </div>
        </div>
      </section>

      <section class="docs-section">
        <h2>Entry types</h2>
        <table class="docs-table">
          <thead>
            <tr>
              <th>Type</th>
              <th>Use for</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>Login</td>
              <td>Usernames, passwords, and URLs for web apps</td>
            </tr>
            <tr>
              <td>API key</td>
              <td>Tokens and environment-specific credentials</td>
            </tr>
            <tr>
              <td>SSH key</td>
              <td>Keys, passphrases, and fingerprints</td>
            </tr>
            <tr>
              <td>Secure note</td>
              <td>Recovery codes, PINs, or free-form secrets</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="docs-section">
        <h2>Get started</h2>
        <ol class="docs-steps">
          <li>Unlock your vault (passkey / Touch ID where supported).</li>
          <li>Open <strong>Secrets Vault</strong> from the rail.</li>
          <li>Create a folder or use the default area for ungrouped entries.</li>
          <li>Click <strong>New entry</strong>, pick a type, fill in fields, and save.</li>
        </ol>
        <p class="docs-prose muted">
          Quick actions from the command palette (⌘K): new login, API key, SSH key, or secure note.
        </p>
      </section>

      <section class="docs-section">
        <h2>Day-to-day use</h2>
        <ul class="docs-list">
          <li><strong>Search</strong> — find entries by title or metadata from the vault sidebar</li>
          <li><strong>Filter</strong> — narrow by entry type or tags</li>
          <li>
            <strong>Copy</strong> — copy username or secret to the clipboard; reveal is temporary
          </li>
          <li>
            <strong>Generator</strong>
            — open the rail <strong>Generator</strong>
            for strong passwords (can apply into a new or open entry)
          </li>
          <li><strong>Lock</strong> — use the top bar to lock the vault when you step away</li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Backup and multi-device</h2>
        <p class="docs-prose">
          Secrets are included in <strong>Trusted Folder</strong>
          backups (<code>secrets.loro.enc</code> inside <code>.suchconfig</code>). Configure Trusted Folder in Settings so a lost laptop does not mean lost passwords.
        </p>
        <p class="docs-prose">
          For live sync between two desktops on the same Wi‑Fi, pair devices under Settings → WiFi / LAN devices and enable LAN sync when available.
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="trusted-folder"
          >
            Trusted Folder guide
          </button>
          ·
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="wifi-p2p-sync"
          >
            WiFi P2P guide
          </button>
        </p>
      </section>

      <section class="docs-section">
        <h2>Security habits</h2>
        <ul class="docs-list">
          <li>Lock the vault on shared machines when you finish a session.</li>
          <li>
            Do not paste secrets into chat or tickets — use placeholders in project notes where possible.
          </li>
          <li>
            Export encrypted archives only when you intend to share; treat them like password database files.
          </li>
        </ul>
      </section>
    </article>
    """
  end
end
