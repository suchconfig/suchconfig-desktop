defmodule SuchConfigDesktopWeb.Components.ProjectVault.LocalBrokerModal do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Modal

  alias SuchConfigDesktopWeb.Components.ProjectVault.BrokerUpgradeCard
  alias SuchConfigDesktopWeb.Components.ProjectVault.ProjectBrokerPanel

  attr :show, :boolean, default: false
  attr :local_broker_license_enabled?, :boolean, default: false
  attr :broker_project_enabled, :boolean, default: false
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

  def local_broker_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="local-broker-modal"
      on_cancel="close_local_broker_modal"
      size="md"
    >
      <.modal_head on_close="close_local_broker_modal" />
      <.modal_body>
        <BrokerUpgradeCard.broker_upgrade_card :if={!@local_broker_license_enabled?} />
        <ProjectBrokerPanel.project_broker_panel
          :if={@local_broker_license_enabled?}
          broker_enabled={@broker_project_enabled}
          broker_scope_id={@broker_scope_id}
          broker_allowed_domains={@broker_allowed_domains}
          broker_services={@broker_services}
          broker_cli_snippet={@broker_cli_snippet}
          broker_snippet_copied={@broker_snippet_copied}
          broker_running={@broker_running}
          broker_socket_path={@broker_socket_path}
          broker_runtime_scope_id={@broker_runtime_scope_id}
          broker_proxy_enabled={@broker_proxy_enabled}
          broker_proxy_url={@broker_proxy_url}
          broker_proxy_ca_fingerprint={@broker_proxy_ca_fingerprint}
          broker_proxy_ca_pinned={@broker_proxy_ca_pinned}
          broker_starting={@broker_starting}
          broker_stopping={@broker_stopping}
          broker_runtime_error={@broker_runtime_error}
        />
      </.modal_body>
      <.modal_foot :if={!@local_broker_license_enabled?}>
        <button
          type="button"
          id="broker-upgrade-close-button"
          phx-click="close_local_broker_modal"
          class="btn sm"
        >
          Close
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end
end
