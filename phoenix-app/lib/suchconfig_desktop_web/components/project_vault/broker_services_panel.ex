defmodule SuchConfigDesktopWeb.Components.ProjectVault.BrokerServicesPanel do
  @moduledoc false

  use Phoenix.Component

  attr :broker_services, :list, default: []

  def broker_services_panel(assigns) do
    ~H"""
    <section id="broker-services-panel" class="broker-services-panel">
      <div class="broker-services-head">
        <span class="k">Service rules</span>
        <button
          type="button"
          class="btn xs"
          id="broker-service-add"
          phx-click="add_broker_service"
        >
          Add service
        </button>
      </div>

      <p class="broker-services-hint">
        Host patterns select which placeholder to inject. Used by
        <span class="mono">broker discover</span>
        and host-driven <span class="mono">api call</span>.
      </p>

      <div :if={@broker_services == []} class="broker-services-empty" id="broker-services-empty">
        No service rules yet.
      </div>

      <div
        :for={{service, index} <- Enum.with_index(@broker_services)}
        class="broker-service-row"
        id={"broker-service-row-#{index}"}
      >
        <label class="broker-field">
          <span class="k">Name</span>
          <input
            type="text"
            name={"services[#{index}][name]"}
            id={"broker-service-name-#{index}"}
            value={service["name"]}
            placeholder="httpbin"
            autocomplete="off"
          />
        </label>
        <label class="broker-field">
          <span class="k">Host</span>
          <input
            type="text"
            name={"services[#{index}][host]"}
            id={"broker-service-host-#{index}"}
            value={service["host"]}
            placeholder="httpbin.org"
            autocomplete="off"
            class="mono"
          />
        </label>
        <label class="broker-field">
          <span class="k">Placeholder</span>
          <input
            type="text"
            name={"services[#{index}][placeholder]"}
            id={"broker-service-placeholder-#{index}"}
            value={service["placeholder"]}
            placeholder="__HTTPBIN_TOKEN__"
            autocomplete="off"
            class="mono"
          />
        </label>
        <label class="broker-field">
          <span class="k">Inject as</span>
          <select
            name={"services[#{index}][inject_as]"}
            id={"broker-service-inject-#{index}"}
          >
            <option value="bearer" selected={service["inject_as"] == "bearer"}>bearer</option>
            <option value="header" selected={service["inject_as"] == "header"}>header</option>
            <option value="query" selected={service["inject_as"] == "query"}>query</option>
          </select>
        </label>
        <button
          type="button"
          class="btn xs"
          id={"broker-service-remove-#{index}"}
          phx-click="remove_broker_service"
          phx-value-index={index}
        >
          Remove
        </button>
      </div>
    </section>
    """
  end
end
