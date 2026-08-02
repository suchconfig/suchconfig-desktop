defmodule SuchConfigDesktopWeb.Components.Docs.WifiP2pSyncGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Sync & backup</div>
        <h1>WiFi P2P sync</h1>
        <p class="docs-lede">
          Pair two SuchConfig desktops on the same Wi‑Fi and keep vaults aligned in near real time — direct device-to-device on your network, with no cloud sync in the middle. Unlike 1Password, LastPass, or Bitwarden, your vault is not routed through a vendor's servers to reach your other computer.
        </p>
      </header>

      <section class="docs-section">
        <h2>Trusted Folder vs WiFi P2P</h2>
        <table class="docs-table">
          <thead>
            <tr>
              <th></th>
              <th>Trusted Folder</th>
              <th>WiFi P2P</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><strong>Best for</strong></td>
              <td>Backup & recovery</td>
              <td>Live sync at home or office</td>
            </tr>
            <tr>
              <td><strong>How data moves</strong></td>
              <td>Your iCloud / Dropbox / NAS</td>
              <td>Directly between paired computers</td>
            </tr>
            <tr>
              <td><strong>Lost device?</strong></td>
              <td>Yes — restore from your folder</td>
              <td>Not alone — use Trusted Folder too</td>
            </tr>
            <tr>
              <td><strong>Typical speed</strong></td>
              <td>Seconds to minutes</td>
              <td>Near instant on same LAN (when live sync ships)</td>
            </tr>
          </tbody>
        </table>
        <div class="docs-callout">
          <.icon name="key" size={16} />
          <div>
            <strong>Recommended:</strong>
            enable both. Trusted Folder is your safe deposit box; WiFi P2P is the fast lane when two machines are on the same network.
          </div>
        </div>
      </section>

      <section class="docs-section">
        <h2>Why no cloud?</h2>
        <p class="docs-prose">
          SuchConfig does not run vault sync servers. WiFi P2P traffic stays on your local network between devices you explicitly paired. Your encrypted backups can still live in
          <em>your</em>
          iCloud or Dropbox via Trusted Folder — that is your storage, not ours.
        </p>
      </section>

      <section class="docs-section">
        <h2>Pair a second computer</h2>
        <p class="docs-prose">
          Device pairing is available today in <strong>Settings → WiFi / LAN devices</strong>.
        </p>
        <ol class="docs-steps">
          <li>
            On the computer that <strong>starts</strong>
            pairing: choose <strong>I'm starting on this computer</strong>.
          </li>
          <li>
            Copy the pairing code (or scan the QR code if available) and send it to the other machine.
          </li>
          <li>
            On the <strong>joining</strong>
            computer: choose <strong>I'm joining</strong>, paste the code, and confirm the 6-character verify code matches.
          </li>
          <li>Copy the response code back to the starting computer and complete pairing.</li>
        </ol>
        <p class="docs-prose muted">
          Each device gets a long-lived identity. Only paired devices are trusted — random machines on your Wi‑Fi cannot sync with you.
        </p>
      </section>

      <section class="docs-section">
        <h2>What's shipping next</h2>
        <ul class="docs-list">
          <li><strong>Today:</strong> pairing wizard and paired-device list</li>
          <li>
            <strong>Coming:</strong>
            automatic discovery on your LAN and live CRDT delta sync between paired peers
          </li>
        </ul>
        <p class="docs-prose muted">
          Until live LAN sync ships, use Trusted Folder for day-to-day multi-device backup, or pair devices now so they are ready when sync goes live.
        </p>
      </section>

      <section class="docs-section">
        <h2>When LAN sync is not available</h2>
        <ul class="docs-list">
          <li>Guest or hotel Wi‑Fi with device isolation</li>
          <li>VPNs that block local multicast</li>
          <li>Only one device online at a time</li>
        </ul>
        <p class="docs-prose">
          Use Trusted Folder or export a <code>.suchvault</code>
          archive. Your vault always works offline locally — sync layers are optional accelerators.
        </p>
      </section>

      <section class="docs-section">
        <h2>Trusted Folder setup</h2>
        <p class="docs-prose">
          If you have not configured a backup folder yet, start with the
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="trusted-folder"
          >
            Trusted Folder
          </button>
          guide.
        </p>
      </section>
    </article>
    """
  end
end
