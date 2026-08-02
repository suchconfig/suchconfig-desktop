defmodule SuchConfigDesktopWeb.ProjectVaultLive.BrokerEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, push_event: 3]

  alias SuchConfigDesktop.ProjectVault

  def assign_broker_state(socket) do
    folder_id = socket.assigns[:selected_folder_id]
    license? = ProjectVault.local_broker_enabled?()

    {enabled, scope_id, domains, services, snippet} =
      case folder_id && ProjectVault.broker_scope_for_folder(folder_id) do
        {:ok, scope} ->
          sid = scope.scope_id || ""

          {scope.enabled, sid, scope.allowed_domains || "", scope.services || [],
           ProjectVault.broker_cli_snippet(sid)}

        _ ->
          {false, "", "", [], ""}
      end

    socket =
      assign(socket,
        local_broker_license_enabled?: license?,
        broker_project_enabled: enabled,
        broker_scope_id: scope_id,
        broker_allowed_domains: domains,
        broker_services: services,
        broker_cli_snippet: snippet,
        broker_snippet_copied: false,
        broker_running: false,
        broker_socket_path: "",
        broker_runtime_scope_id: "",
        broker_starting: false,
        broker_stopping: false,
        broker_runtime_error: nil
      )

    if connected?(socket) and license? and enabled and scope_id != "" do
      push_event(socket, "fetch_broker_status", %{scope_id: scope_id})
    else
      socket
    end
  end

  def open_local_broker_modal(_params, socket) do
    if socket.assigns[:selected_folder_id] do
      socket =
        socket
        |> assign_broker_state()
        |> assign(show_local_broker_modal: true, error: nil)

      {:noreply, socket}
    else
      {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}
    end
  end

  def close_local_broker_modal(_params, socket) do
    {:noreply, assign(socket, show_local_broker_modal: false)}
  end

  def toggle_project_broker(_params, socket) do
    folder_id = socket.assigns.selected_folder_id

    cond do
      not ProjectVault.local_broker_enabled?() ->
        {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}

      true ->
        next = !socket.assigns.broker_project_enabled

        case ProjectVault.update_project_broker(folder_id, %{broker_enabled: next}) do
          {:ok, folder} ->
            socket =
              socket
              |> refresh_folders()
              |> assign(
                broker_project_enabled: folder.broker_enabled == true,
                info:
                  if(folder.broker_enabled,
                    do: "Local Broker enabled for project.",
                    else: "Local Broker disabled for project."
                  ),
                error: nil
              )

            {:noreply, assign_broker_state(socket)}

          {:error, :license_local_broker_required} ->
            {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error: "Could not update Broker settings.", info: nil)}
        end
    end
  end

  def broker_form_change(params, socket) do
    scope_id = Map.get(params, "broker_scope_id", "") |> to_string()
    domains = Map.get(params, "broker_allowed_domains", "") |> to_string()
    services = services_from_params(params, socket.assigns[:broker_services] || [])

    {:noreply,
     assign(socket,
       broker_scope_id: scope_id,
       broker_allowed_domains: domains,
       broker_services: services,
       broker_cli_snippet: ProjectVault.broker_cli_snippet(scope_id),
       broker_snippet_copied: false
     )}
  end

  def add_broker_service(_params, socket) do
    services =
      (socket.assigns[:broker_services] || []) ++
        [
          %{
            "name" => "",
            "host" => "",
            "placeholder" => "",
            "inject_as" => "bearer"
          }
        ]

    {:noreply, assign(socket, broker_services: services)}
  end

  def remove_broker_service(params, socket) do
    index =
      case Integer.parse(to_string(Map.get(params, "index", "-1"))) do
        {n, _} -> n
        :error -> -1
      end

    services =
      (socket.assigns[:broker_services] || [])
      |> Enum.with_index()
      |> Enum.reject(fn {_service, i} -> i == index end)
      |> Enum.map(fn {service, _} -> service end)

    {:noreply, assign(socket, broker_services: services)}
  end

  def save_broker_scope(params, socket) do
    folder_id = socket.assigns.selected_folder_id

    cond do
      not ProjectVault.local_broker_enabled?() ->
        {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}

      true ->
        services = services_from_params(params, socket.assigns[:broker_services] || [])

        attrs = %{
          broker_scope_id: Map.get(params, "broker_scope_id", "") |> to_string(),
          broker_allowed_domains: Map.get(params, "broker_allowed_domains", "") |> to_string(),
          broker_services: services,
          broker_enabled:
            Map.has_key?(params, "broker_enabled") or socket.assigns.broker_project_enabled
        }

        case ProjectVault.update_project_broker(folder_id, attrs) do
          {:ok, folder} ->
            sid = folder.broker_scope_id || ""

            socket =
              socket
              |> refresh_folders()
              |> assign(
                broker_project_enabled: folder.broker_enabled == true,
                broker_scope_id: sid,
                broker_allowed_domains: folder.broker_allowed_domains || "",
                broker_services: ProjectVault.parse_broker_services(folder.broker_services),
                broker_cli_snippet: ProjectVault.broker_cli_snippet(sid),
                broker_snippet_copied: false,
                info: "Broker settings saved.",
                error: nil
              )

            maybe_rewrite_manifest(socket, folder_id)
            {:noreply, assign_broker_state(socket)}

          {:error, :license_local_broker_required} ->
            {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

          {:error, _} ->
            {:noreply, assign(socket, error: "Could not save Broker settings.", info: nil)}
        end
    end
  end

  defp maybe_rewrite_manifest(socket, folder_id) do
    pw = socket.assigns[:vault_password]

    if is_binary(pw) and String.trim(pw) != "" do
      _ = ProjectVault.write_broker_scope_manifest_file(folder_id, pw)
    end

    :ok
  end

  defp services_from_params(params, fallback) do
    case Map.get(params, "services") do
      %{} = nested ->
        nested
        |> Enum.sort_by(fn {key, _} ->
          case Integer.parse(to_string(key)) do
            {n, _} -> n
            :error -> 9999
          end
        end)
        |> Enum.map(fn {_key, value} -> value end)
        |> ProjectVault.parse_broker_services()
        |> then(fn parsed ->
          if parsed == [] and nested != %{} do
            draft_services_from_nested(nested)
          else
            parsed
          end
        end)

      _ ->
        fallback
    end
  end

  defp draft_services_from_nested(nested) do
    nested
    |> Enum.sort_by(fn {key, _} ->
      case Integer.parse(to_string(key)) do
        {n, _} -> n
        :error -> 9999
      end
    end)
    |> Enum.map(fn {_key, value} ->
      %{
        "name" => value |> Map.get("name", "") |> to_string(),
        "host" => value |> Map.get("host", "") |> to_string(),
        "placeholder" => value |> Map.get("placeholder", "") |> to_string(),
        "inject_as" => value |> Map.get("inject_as", "bearer") |> to_string()
      }
    end)
  end

  def copy_broker_cli_snippet(_params, socket) do
    snippet = socket.assigns[:broker_cli_snippet] || ""

    if snippet == "" do
      {:noreply,
       assign(socket, error: "Set a scope id before copying the CLI snippet.", info: nil)}
    else
      {:noreply,
       socket
       |> assign(broker_snippet_copied: true, info: nil, error: nil)
       |> push_event("copy_to_clipboard", %{content: snippet})}
    end
  end

  def toggle_broker_proxy(params, socket) do
    enabled = truthy?(Map.get(params, "value"))

    if socket.assigns[:broker_running] do
      {:noreply,
       assign(socket,
         broker_proxy_enabled: socket.assigns[:broker_proxy_enabled] || false,
         error: "Stop the Broker before changing transparent proxy mode.",
         info: nil
       )}
    else
      {:noreply,
       assign(socket,
         broker_proxy_enabled: enabled,
         error: nil,
         info: nil
       )}
    end
  end

  def start_project_broker(_params, socket) do
    folder_id = socket.assigns.selected_folder_id

    cond do
      not ProjectVault.local_broker_enabled?() ->
        {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}

      true ->
        pw = socket.assigns[:vault_password]

        unless ProjectVault.project_broker_enabled?(folder_id) do
          {:noreply,
           assign(socket,
             error: "Enable Local Broker for this project before starting.",
             info: nil
           )}
        else
          cond do
            not (is_binary(pw) and String.trim(pw) != "") ->
              {:noreply,
               assign(socket,
                 error: "Unlock the vault before starting the broker.",
                 info: nil
               )}

            true ->
              start_project_broker_with_password(folder_id, pw, socket)
          end
        end
    end
  end

  defp start_project_broker_with_password(folder_id, pw, socket) do
    case ProjectVault.broker_scope_manifest_for_folder(folder_id, pw) do
      {:ok, manifest} ->
        _ = ProjectVault.write_broker_scope_manifest_file(folder_id, pw)

        timeout_ref = Process.send_after(self(), :broker_start_timeout, 15_000)

        {:noreply,
         socket
         |> assign(
           broker_starting: true,
           broker_runtime_error: nil,
           info: nil,
           error: nil,
           broker_start_timeout_ref: timeout_ref
         )
         |> push_event("invoke_broker_start", %{
           scope_id: manifest.scope_id,
           manifest: manifest_to_json(manifest),
           enable_proxy: socket.assigns[:broker_proxy_enabled] || false
         })}

      {:error, :broker_disabled} ->
        {:noreply,
         assign(socket,
           error: "Enable Local Broker for this project before starting.",
           info: nil
         )}

      {:error, :scope_id_required} ->
        {:noreply, assign(socket, error: "Set a scope id before starting the broker.", info: nil)}

      {:error, :not_found} ->
        {:noreply, assign(socket, error: "Project folder not found.", info: nil)}

      {:error, _} ->
        {:noreply, assign(socket, error: "Could not export broker scope manifest.", info: nil)}
    end
  end

  def stop_project_broker(_params, socket) do
    cond do
      not ProjectVault.local_broker_enabled?() ->
        {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

      true ->
        {:noreply,
         socket
         |> assign(broker_stopping: true, broker_runtime_error: nil, info: nil, error: nil)
         |> push_event("invoke_broker_stop", %{})}
    end
  end

  def broker_start_result(params, socket) do
    {:noreply, apply_runtime_status(clear_broker_start_timeout(socket), params, starting: false)}
  end

  def broker_stop_result(params, socket) do
    {:noreply, apply_runtime_status(socket, params, stopping: false)}
  end

  def broker_status_result(params, socket) do
    {:noreply, apply_runtime_status(socket, params, starting: false, stopping: false)}
  end

  def broker_start_timeout(socket) do
    if socket.assigns[:broker_starting] do
      assign(socket,
        broker_starting: false,
        broker_runtime_error:
          "Broker start timed out. Restart the desktop app (pnpm run tauri:dev), confirm scope id matches, and try again."
      )
    else
      socket
    end
  end

  defp apply_runtime_status(socket, params, opts) do
    running = truthy?(Map.get(params, "running"))
    error = blank_to_nil(Map.get(params, "error") || Map.get(params, "message"))

    socket
    |> assign(
      broker_starting: Keyword.get(opts, :starting, socket.assigns[:broker_starting] || false),
      broker_stopping: Keyword.get(opts, :stopping, socket.assigns[:broker_stopping] || false),
      broker_running: running,
      broker_socket_path: to_string(Map.get(params, "socket_path", "")),
      broker_runtime_scope_id: to_string(Map.get(params, "scope_id", "")),
      broker_proxy_enabled:
        if(running,
          do: truthy?(Map.get(params, "proxy_enabled")),
          else: socket.assigns[:broker_proxy_enabled] || false
        ),
      broker_proxy_url: to_string(Map.get(params, "proxy_url", "")),
      broker_proxy_ca_fingerprint: to_string(Map.get(params, "proxy_ca_fingerprint", "")),
      broker_proxy_ca_pinned: truthy?(Map.get(params, "proxy_ca_pinned")),
      broker_runtime_error: if(running, do: nil, else: error)
    )
  end

  defp manifest_to_json(manifest) do
    ProjectVault.manifest_to_json_map(manifest)
    |> Map.update("credentials", %{}, &stringify_credentials/1)
  end

  defp stringify_credentials(credentials) when is_map(credentials) do
    credentials
    |> Enum.map(fn {key, value} -> {to_string(key), to_string(value)} end)
    |> Map.new()
  end

  defp stringify_credentials(_), do: %{}

  defp truthy?(value) when value in [true, "true", 1, "1", "on"], do: true
  defp truthy?(_), do: false

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: to_string(value)

  defp clear_broker_start_timeout(socket) do
    case socket.assigns[:broker_start_timeout_ref] do
      ref when is_reference(ref) -> Process.cancel_timer(ref)
      _ -> :ok
    end

    assign(socket, broker_start_timeout_ref: nil)
  end

  defp refresh_folders(socket) do
    assign(socket, folders: ProjectVault.list_project_folders())
  end
end
