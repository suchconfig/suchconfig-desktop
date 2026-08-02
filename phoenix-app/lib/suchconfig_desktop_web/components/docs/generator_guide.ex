defmodule SuchConfigDesktopWeb.Components.Docs.GeneratorGuide do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def guide(assigns) do
    ~H"""
    <article class="docs-article-inner">
      <header class="docs-article-head">
        <div class="eyebrow">Tools</div>
        <h1>Generator</h1>
        <p class="docs-lede">
          Cryptographically secure passwords, passphrases, and usernames — generated entirely on your device. Nothing is sent to SuchConfig servers or third-party generator websites.
        </p>
      </header>

      <section class="docs-section">
        <h2>Why local generation matters</h2>
        <p class="docs-prose">
          Hosted tools (including password managers’ web generators) run in a browser tab you do not control. A generated secret can linger in memory, analytics, or server logs. SuchConfig’s generator runs inside the desktop app using the
          <code>suchconfig_core</code>
          Elixir library — the same code path whether you open the rail drawer or apply a value to a Secrets Vault entry.
        </p>
        <div class="docs-callout">
          <.icon name="wand" size={16} />
          <div>
            <strong>Local-first security:</strong>
            roll → copy or apply. No network call, no cloud storage of the value, no dependency on Bitwarden or similar hosted generators.
          </div>
        </div>
      </section>

      <section class="docs-section">
        <h2>Open the drawer</h2>
        <ul class="docs-list">
          <li>Click the <strong>Generator</strong> (wand) button in the rail</li>
          <li>Or use the command palette (⌘K) → Open Password Generator</li>
          <li>
            From Secrets Vault, open the generator while editing an entry to
            <strong>Set Password</strong>
            or <strong>Set Username</strong>
            directly
          </li>
        </ul>
        <p class="docs-prose muted">
          The tagline in the drawer — “such entropy — never leaves the device” — reflects this design.
        </p>
      </section>

      <section class="docs-section">
        <h2>Three modes</h2>
        <table class="docs-table">
          <thead>
            <tr>
              <th>Mode</th>
              <th>What you get</th>
              <th>Engine</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><strong>Password</strong></td>
              <td>
                Random string with configurable length and character classes (upper, lower, numbers, symbols)
              </td>
              <td><code>SuchConfigCore.Generators.PasswordGenerator</code></td>
            </tr>
            <tr>
              <td><strong>Passphrase</strong></td>
              <td>
                Random words from the EFF large wordlist, joined with hyphens; optional digit suffix
              </td>
              <td>Same module + bundled wordlist file</td>
            </tr>
            <tr>
              <td><strong>Username</strong></td>
              <td>
                Random lowercase alphanumeric handle, or a Gmail <code>+alias</code>
                address with random or patterned suffix
              </td>
              <td>PasswordGenerator for random parts; alias patterns expanded locally</td>
            </tr>
          </tbody>
        </table>
      </section>

      <section class="docs-section">
        <h2>Cryptography (passwords & passphrases)</h2>
        <p class="docs-prose">
          Generation uses Erlang/OTP <code>:crypto.strong_rand_bytes/1</code>
          — the same CSPRNG the BEAM uses for TLS and other crypto. Character and word indices are chosen with
          <strong>rejection sampling</strong>
          so each outcome in the pool is equally likely (no modulo bias).
        </p>
        <ul class="docs-list">
          <li>
            <strong>Passwords</strong>
            — at least one character from each enabled class, then fill and shuffle; optional exclusion of ambiguous characters (<code>0O1lI</code>)
          </li>
          <li>
            <strong>Passphrases</strong>
            — words loaded from the embedded EFF large wordlist (offline file shipped with <code>suchconfig_core</code>, not fetched at runtime)
          </li>
          <li>
            <strong>Strength meter</strong>
            — estimated entropy in bits, mapped to labels (very weak → very strong) and rough offline crack times at 10¹⁰ guesses/sec
          </li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Usernames & Gmail plus aliases</h2>
        <p class="docs-prose">
          <strong>Random username</strong>
          mode builds a lowercase + digits string using the same secure password generator (symbols and uppercase off, ambiguous chars excluded).
        </p>
        <p class="docs-prose">
          <strong>Gmail plus alias</strong>
          mode keeps your real address private: enter <code>you@gmail.com</code>
          and SuchConfig produces <code>you+suffix@gmail.com</code>. Gmail delivers mail to the same inbox; sites see a unique login per signup.
        </p>
        <ul class="docs-list">
          <li><strong>Random suffix</strong> — cryptographically random token (length slider)</li>
          <li>
            <strong>Pattern suffix</strong>
            — tokens like <code>{"{env}"}</code>, <code>{"{project}"}</code>, <code>{"{date}"}</code>, <code>{"{rand}"}</code>,
            <code>{"{time}"}</code>
            for readable staging accounts
          </li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Privacy & storage</h2>
        <ul class="docs-list">
          <li>Generated values are <strong>not</strong> uploaded or logged by SuchConfig</li>
          <li>
            <strong>Recent rolls</strong>
            in the drawer are the last few values from this session only — convenient for copy, not a permanent history
          </li>
          <li>
            When you <strong>Set Password</strong>
            on a vault entry, only then does the value enter encrypted vault storage (same as typing it yourself)
          </li>
          <li>
            Clipboard copy uses the native Tauri bridge; treat the clipboard like any password manager would
          </li>
        </ul>
      </section>

      <section class="docs-section">
        <h2>Compared to cloud password managers</h2>
        <table class="docs-table">
          <thead>
            <tr>
              <th></th>
              <th>Hosted generator</th>
              <th>SuchConfig Generator</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><strong>Where it runs</strong></td>
              <td>Vendor website or extension</td>
              <td>Your machine (Elixir + OTP crypto)</td>
            </tr>
            <tr>
              <td><strong>Network</strong></td>
              <td>May phone home for analytics or sync context</td>
              <td>None for generation</td>
            </tr>
            <tr>
              <td><strong>Wordlist / algorithm</strong></td>
              <td>Often opaque</td>
              <td>Open <code>suchconfig_core</code> source; EFF wordlist; documented entropy math</td>
            </tr>
          </tbody>
        </table>
        <p class="docs-prose">
          Pair with
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="secrets-vault"
          >
            Secrets Vault
          </button>
          to store what you generate, and
          <button
            type="button"
            class="docs-inline-link"
            phx-click="select_doc"
            phx-value-id="trusted-folder"
          >
            Trusted Folder
          </button>
          for encrypted backup.
        </p>
      </section>
    </article>
    """
  end
end
