defmodule SuchConfigDesktopWeb.Components.ProjectVault.ProjectBrokerPanel do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  alias SuchConfigDesktopWeb.Components.ProjectVault.BrokerServicesPanel

  attr :broker_enabled, :boolean, default: false
  attr :broker_scope_id, :string, default: ""
  attr :broker_allowed_domains, :string, default: ""
  attr :broker_services, :list, default: []
  attr :broker_cli_snippet, :string, default: ""
  attr :broker_snippet_copied, :boolean, default: false
  attr :broker_running, :boolean, default: false
  attr :broker_socket_path, :string, default: ""
  attr :broker_runtime_scope_id, :string, default: ""
  attr :broker_proxy_enabled, :boolean, default: false
  attr :broker_proxy_url, :string, default: ""
  attr :broker_proxy_ca_fingerprint, :string, default: ""
  attr :broker_proxy_ca_pinned, :boolean, default: false
  attr :broker_starting, :boolean, default: false
  attr :broker_stopping, :boolean, default: false
  attr :broker_runtime_error, :string, default: nil

  def project_broker_panel(assigns) do
    ~H"""
    <section id="project-broker-panel" class="broker-panel">
      <div class="broker-panel-head">
        <.icon name="key" size={16} />
        <h3>Local Broker</h3>
        <span class={["broker-panel-badge", @broker_enabled && "on"]}>
          {if @broker_enabled, do: "On", else: "Off"}
        </span>
      </div>

      <form id="project-broker-form" phx-submit="save_broker_scope" phx-change="broker_form_change">
        <label class="broker-toggle-row">
          <input
            type="checkbox"
            name="broker_enabled"
            value="true"
            checked={@broker_enabled}
            phx-click="toggle_project_broker"
          />
          <span>Enable Local Broker for this project</span>
        </label>

        <label class="broker-field">
          <span class="k">Scope id</span>
          <input
            type="text"
            name="broker_scope_id"
            id="broker-scope-id"
            value={@broker_scope_id}
            placeholder="my-app-staging"
            autocomplete="off"
            class="mono"
          />
        </label>

        <label class="broker-field">
          <span class="k">Allowed domains</span>
          <input
            type="text"
            name="broker_allowed_domains"
            id="broker-allowed-domains"
            value={@broker_allowed_domains}
            placeholder="api.stripe.com, api.github.com"
            autocomplete="off"
          />
        </label>

        <BrokerServicesPanel.broker_services_panel broker_services={@broker_services} />

        <div class="broker-panel-actions">
          <button type="submit" class="btn sm primary" id="broker-save-scope">
            Save Broker settings
          </button>
          <button
            type="button"
            class="btn sm"
            id="broker-close-button"
            phx-click="close_local_broker_modal"
          >
            Close
          </button>
        </div>
      </form>

      <div :if={@broker_enabled and @broker_scope_id != ""} class="broker-runtime" id="broker-runtime">
        <div class="broker-runtime-head">
          <span class="k">Runtime</span>
          <span class={["broker-runtime-badge", @broker_running && "on"]}>
            {broker_runtime_label(@broker_running, @broker_starting, @broker_stopping)}
          </span>
        </div>

        <p :if={@broker_runtime_error} class="broker-runtime-error" id="broker-runtime-error">
          {@broker_runtime_error}
        </p>

        <label class="broker-toggle-row" id="broker-proxy-toggle-row">
          <input
            type="checkbox"
            id="broker-proxy-toggle"
            checked={@broker_proxy_enabled}
            value={to_string(!@broker_proxy_enabled)}
            phx-click="toggle_broker_proxy"
            disabled={@broker_running or @broker_starting or @broker_stopping}
          />
          <span>Enable transparent HTTPS proxy</span>
        </label>

        <div :if={@broker_proxy_enabled} class="broker-runtime-error" id="broker-proxy-warning">
          This opt-in mode decrypts HTTPS from wrapped child processes using a local CA. Only
          scope-allowlisted service hosts are accepted, and real credentials stay inside the Broker.
        </div>

        <dl :if={@broker_running} class="broker-runtime-meta" id="broker-runtime-meta">
          <div>
            <dt>Scope</dt>
            <dd class="mono">{@broker_runtime_scope_id}</dd>
          </div>
          <div>
            <dt>Socket</dt>
            <dd class="mono" id="broker-socket-path">{@broker_socket_path}</dd>
          </div>
          <div :if={@broker_proxy_enabled and @broker_proxy_url != ""}>
            <dt>HTTPS proxy</dt>
            <dd class="mono" id="broker-proxy-url">{@broker_proxy_url}</dd>
          </div>
          <div :if={@broker_proxy_enabled}>
            <dt>Local CA</dt>
            <dd id="broker-proxy-ca-status">
              <span
                :if={@broker_proxy_ca_fingerprint != ""}
                class="mono"
                id="broker-proxy-ca-fingerprint"
              >
                {@broker_proxy_ca_fingerprint}
              </span>
              <span :if={@broker_proxy_ca_fingerprint != "" and @broker_proxy_ca_pinned}>
                {" · pinned in secure storage"}
              </span>
              <span :if={@broker_proxy_ca_fingerprint == ""}>
                Exported for wrapped child trust
              </span>
            </dd>
          </div>
        </dl>

        <div class="broker-runtime-actions">
          <button
            :if={!@broker_running}
            type="button"
            class="btn sm primary"
            id="broker-start-button"
            phx-click="start_project_broker"
            disabled={@broker_starting}
          >
            {if @broker_starting, do: "Starting…", else: "Start Broker"}
          </button>
          <button
            :if={@broker_running}
            type="button"
            class="btn sm broker-stop-button"
            id="broker-stop-button"
            phx-click="stop_project_broker"
            disabled={@broker_stopping}
          >
            {if @broker_stopping, do: "Stopping…", else: "Stop Broker"}
          </button>
        </div>
      </div>

      <div :if={@broker_cli_snippet != ""} class="broker-cli-snippet" id="broker-cli-snippet">
        <div class="broker-cli-snippet-head">
          <span class="k">CLI</span>
          <button
            type="button"
            id="copy-broker-cli-snippet"
            class="btn xs"
            phx-click="copy_broker_cli_snippet"
            phx-hook="CopyButton"
            data-copy={@broker_cli_snippet}
          >
            {if @broker_snippet_copied, do: "Copied", else: "Copy"}
          </button>
        </div>
        <pre class="mono">{@broker_cli_snippet}</pre>
      </div>
    </section>
    """
  end

  defp broker_runtime_label(true, _, _), do: "Running"
  defp broker_runtime_label(false, true, _), do: "Starting…"
  defp broker_runtime_label(false, _, true), do: "Stopping…"
  defp broker_runtime_label(false, _, _), do: "Stopped"
end
