defmodule SuchConfigDesktopWeb.AboutLive do
  use SuchConfigDesktopWeb, :live_view

  def mount(_params, _session, socket) do
    version = Application.spec(:suchconfig_desktop, :vsn) |> to_string()
    major = version |> String.split(".") |> List.first() |> Kernel.||("0")

    {:ok,
     assign(socket,
       page_title: "About - SuchConfig",
       version: version,
       version_major: major,
       platform_label: platform_label()
     )}
  end

  def render(assigns) do
    ~H"""
    <div id="about-live-root">
      <section class="page-head">
        <div>
          <div class="eyebrow">About</div>
          <h1>such config,<br /><em>very local.</em></h1>
          <div class="lede">
            A local-first vault for developers — sensitive projects, passwords, configs, and secrets on your machine. No accounts. No vendor vault cloud. Merge-safe history across your own devices.
          </div>
        </div>
        <div class="meta">
          <div><b>v{@version}</b></div>
          <div class="stat">v{@version_major}<sup>desktop</sup></div>
          <div class="muted" style="margin-top: 10px">{@platform_label}</div>
        </div>
      </section>

      <div class="about-vision-intro">
        <div class="eyebrow">Our vision</div>
        <p class="about-prose">
          SuchConfig exists so engineers can stop juggling Bitwarden, scattered
          <span class="mono">.env</span>
          files, and ad hoc notes — one trusted app built for how you actually work.
        </p>
      </div>

      <div class="split">
        <div class="card" id="about-vision-source-of-truth">
          <h4>One source of truth</h4>
          <p class="about-prose">
            <span class="serif" style="font-style: italic">Project Vault</span>
            for configs, prompts, and archives.
            <span class="serif" style="font-style: italic">Secrets Vault</span>
            for logins, API keys, and SSH material. Local tools like the Generator — plus backup and LAN sync you control, not a hosted password-manager cloud.
          </p>
        </div>
        <div class="card" id="about-vision-security">
          <h4>Data sovereignty & security</h4>
          <p class="about-prose">
            Vault data stays on your device, encrypted at rest, unlocked with your passkey. No SuchConfig vault sync server, no telemetry of secret bodies, and clear warnings before anything leaves the machine via export or backup.
          </p>
        </div>
        <div class="card" id="about-vision-local-first">
          <h4>Local-first</h4>
          <p class="about-prose">
            Fully useful offline. CRDT merges let laptop and desktop histories converge without manual conflict resolution. You choose how data moves — iCloud, Dropbox, USB, encrypted archives, or WiFi between paired devices.
          </p>
        </div>
        <div class="card" id="about-vision-ai">
          <h4>AI-augmented workflows</h4>
          <p class="about-prose">
            Keep env schemas and credentials in the vault instead of leaky copies on disk. Placeholders and structured profiles so agents reference names, not plaintext — ship AI-assisted development without pasting your
            <span class="mono">.env</span>
            into chat.
          </p>
        </div>
        <div class="card">
          <h4>Credits</h4>
          <div class="col" style="font-size: 13px; gap: 8px">
            <div>Built by zanuka.io and contributors</div>
            <div class="muted">Type: Instrument Serif · Geist · Geist Mono</div>
            <div class="muted">Crypto: XChaCha20-Poly1305, Argon2id, Ed25519</div>
            <div class="muted">CRDTs: Loro-backed merge</div>
          </div>
        </div>
        <div class="card">
          <h4>Such doge,</h4>
          <div class="big serif" style="font-style: italic">very wow.</div>
          <p class="muted" style="margin-top: 14px; font-size: 13px">
            The name is a wink. The cryptography is not.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp platform_label do
    case :os.type() do
      {:unix, :darwin} -> "macOS · Linux · Windows"
      {:unix, :linux} -> "Linux · macOS · Windows"
      {:win32, _} -> "Windows · macOS · Linux"
      _ -> "macOS · Linux · Windows"
    end
  end
end
