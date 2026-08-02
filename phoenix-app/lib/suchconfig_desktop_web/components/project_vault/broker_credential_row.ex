defmodule SuchConfigDesktopWeb.Components.ProjectVault.BrokerCredentialRow do
  @moduledoc false

  use Phoenix.Component

  attr :broker_ui_enabled?, :boolean, default: false
  attr :broker_item_enabled, :boolean, default: false
  attr :broker_placeholder, :string, default: ""
  attr :broker_credential_kind, :string, default: "api_key"
  attr :broker_inject_as, :string, default: "header"
  attr :selected_vault_item_id, :any, default: nil

  def broker_credential_row(assigns) do
    ~H"""
    <section
      :if={@broker_ui_enabled? && @selected_vault_item_id}
      id="broker-credential-row"
      class="broker-credential-row"
    >
      <div class="broker-credential-head">
        <span class="k">Local Broker</span>
      </div>

      <label class="broker-toggle-row">
        <input
          type="checkbox"
          name="broker_item_enabled"
          checked={@broker_item_enabled}
          phx-click="toggle_item_broker"
          phx-value-enabled={to_string(!@broker_item_enabled)}
        />
        <span>Enable this credential for Broker</span>
      </label>

      <form
        id="broker-placeholder-form"
        phx-submit="save_broker_placeholder"
        class="broker-field-grid"
      >
        <label class="broker-field">
          <span class="k">Placeholder</span>
          <input
            type="text"
            name="broker_placeholder"
            id="broker-placeholder-input"
            value={@broker_placeholder}
            placeholder="__stripe_sk__"
            autocomplete="off"
            class="mono"
          />
        </label>

        <label class="broker-field">
          <span class="k">Kind</span>
          <select name="broker_credential_kind" id="broker-credential-kind">
            <option value="api_key" selected={@broker_credential_kind == "api_key"}>API key</option>
            <option value="bearer" selected={@broker_credential_kind == "bearer"}>Bearer</option>
            <option value="oauth" selected={@broker_credential_kind == "oauth"}>OAuth</option>
          </select>
        </label>

        <label class="broker-field">
          <span class="k">Inject as</span>
          <select name="broker_inject_as" id="broker-inject-as">
            <option value="header" selected={@broker_inject_as == "header"}>Header</option>
            <option value="query" selected={@broker_inject_as == "query"}>Query</option>
            <option value="env" selected={@broker_inject_as == "env"}>Env</option>
          </select>
        </label>

        <button type="submit" class="btn xs" id="broker-save-placeholder">
          Save Broker credential
        </button>
      </form>
    </section>
    """
  end
end
