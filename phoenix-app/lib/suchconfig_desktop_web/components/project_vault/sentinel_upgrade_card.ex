defmodule SuchConfigDesktopWeb.Components.ProjectVault.SentinelUpgradeCard do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def sentinel_upgrade_card(assigns) do
    ~H"""
    <section id="sentinel-upgrade-card" class="broker-panel broker-panel--upgrade">
      <div class="broker-panel-head">
        <.icon name="lock" size={16} />
        <h3>Security Sentinel</h3>
        <span class="broker-panel-badge">Pro</span>
      </div>
      <p class="muted" style="font-size: 13px; margin: 0 0 8px">
        Security Sentinel scans linked projects locally and saves a Report Card and Security Manifest
        in your vault. Free tier includes Project Vault; upgrade to Personal Pro to enable Sentinel.
        Scan engines are not included in free Community Edition.
      </p>
      <p class="muted" style="font-size: 12px; margin: 0">
        Security Sentinel (Pro) — coming with license unlock.
      </p>
    </section>
    """
  end
end
