defmodule SuchConfigDesktopWeb.Components.ProjectVault.BrokerUpgradeCard do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  def broker_upgrade_card(assigns) do
    ~H"""
    <section id="broker-upgrade-card" class="broker-panel broker-panel--upgrade">
      <div class="broker-panel-head">
        <.icon name="lock" size={16} />
        <h3>Local Broker</h3>
        <span class="broker-panel-badge">Pro</span>
      </div>
      <p class="muted" style="font-size: 13px; margin: 0 0 8px">
        Local Broker injects project credentials for agents and CLI without exposing plaintext.
        Free tier includes Project Vault and Secrets Vault; upgrade to Personal Pro to enable Broker.
      </p>
      <p class="muted" style="font-size: 12px; margin: 0">
        Local Broker (Pro) — coming with license unlock.
      </p>
    </section>
    """
  end
end
