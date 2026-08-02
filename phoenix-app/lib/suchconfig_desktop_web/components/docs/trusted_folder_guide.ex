defmodule SuchConfigDesktopWeb.Components.Docs.TrustedFolderGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Sync & backup</div>
        <h1>Trusted Folder</h1>
        <p class="docs-lede">
          Back up your vault to a folder you already own — iCloud Drive, Dropbox, Google Drive, a NAS, or a USB drive. SuchConfig never hosts your data.
        </p>
      </header>

      <section class="docs-section">
        <h2>What it does</h2>
        <p class="docs-prose">
          Trusted Folder writes encrypted snapshot files into a <code>.suchconfig</code>
          subfolder inside the path you choose. When that folder syncs (via iCloud, Dropbox, OneDrive, etc.), your other devices can import the same backup automatically.
        </p>
        <p class="docs-prose muted">
          You do not need to open this folder day to day — SuchConfig manages it. On macOS and Linux, dot folders are often hidden in the file manager; on Windows the folder name is the same and sync works the same way.
        </p>
        <div class="docs-callout">
          <.icon name="folder" size={16} />
          <div>
            <strong>Primary job:</strong>
            backup, recovery, and multi-device continuity — especially if a device is lost or replaced.
          </div>
        </div>
      </section>

      <section class="docs-section">
        <h2>What gets backed up</h2>
        <ul class="docs-list">
          <li>Project folders and project vault items</li>
          <li>Secrets vault entries</li>
        </ul>
        <p class="docs-prose muted">
          Linked project files on disk use a separate sync path. Manual <code>.suchvault</code>
          exports are a different feature for one-off handoffs.
        </p>
      </section>

      <section class="docs-section">
        <h2>Set up (first time)</h2>
        <ol class="docs-steps">
          <li>Unlock your vault if prompted.</li>
          <li>Open <strong>Settings</strong> or complete the onboarding prompt.</li>
          <li>
            Choose <strong>Trusted Folder</strong> and pick a folder (e.g. iCloud Drive/SuchConfig).
          </li>
          <li>SuchConfig creates <code>.suchconfig</code> and writes the first encrypted backup.</li>
        </ol>
      </section>

      <section class="docs-section">
        <h2>When sync runs</h2>
        <p class="docs-prose">
          Sync needs your vault <strong>unlocked</strong>
          and a folder configured. SuchConfig exports automatically when you:
        </p>
        <ul class="docs-list">
          <li>Save a project or secrets entry</li>
          <li>Create or rename a project folder</li>
          <li>Unlock the vault or open the app</li>
          <li>Tap <strong>Sync now</strong> in Settings</li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Status badge</h2>
        <table class="docs-table">
          <thead>
            <tr>
              <th>Badge</th>
              <th>Meaning</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td>✓ Backed up</td>
              <td>Watcher is running and both project and secrets backup files exist.</td>
            </tr>
            <tr>
              <td>· Watching</td>
              <td>Folder is set but one or both backup files are still missing.</td>
            </tr>
            <tr>
              <td>· Paused</td>
              <td>Watcher is not running — check Settings.</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="docs-section">
        <h2>Recover on a new device</h2>
        <ol class="docs-steps">
          <li>Install SuchConfig and unlock with your passkey.</li>
          <li>Point Trusted Folder at the same cloud folder (or copy the backup files).</li>
          <li>Wait for import, or use <strong>Sync now</strong> / integrity check in Settings.</li>
        </ol>
        <p class="docs-prose muted">
          Typical cloud sync latency is seconds to a few minutes — not instant, but durable across time and location.
        </p>
      </section>

      <section class="docs-section">
        <h2>Also use WiFi P2P sync?</h2>
        <p class="docs-prose">
          Yes — they work together. Trusted Folder is your safety net; WiFi P2P adds fast live sync when two computers share the same network. See the
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="wifi-p2p-sync"
          >
            WiFi P2P sync
          </button>
          guide.
        </p>
      </section>
    </article>
    """
  end
end
