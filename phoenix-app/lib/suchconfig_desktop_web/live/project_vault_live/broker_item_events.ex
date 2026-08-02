defmodule SuchConfigDesktopWeb.ProjectVaultLive.BrokerItemEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.BrokerFrontmatter
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey

  def assign_broker_item_state(socket, item, password) do
    broker_ui? =
      socket.assigns[:local_broker_license_enabled?] == true &&
        socket.assigns[:broker_project_enabled] == true

    state =
      if broker_ui? && item && is_binary(password) && password != "" do
        ProjectVault.vault_item_broker_state(item, password)
      else
        %{
          enabled: false,
          placeholder: "",
          credential_kind: "api_key",
          inject_as: "header",
          env_enabled_keys: []
        }
      end

    env_entries =
      if broker_ui? && item && is_binary(password) && password != "" do
        env_broker_entries(item, password)
      else
        []
      end

    assign(socket,
      broker_ui_enabled?: broker_ui?,
      broker_item_enabled: state.enabled,
      broker_placeholder: state.placeholder,
      broker_credential_kind: state.credential_kind,
      broker_inject_as: state.inject_as,
      broker_env_enabled_keys: state.env_enabled_keys,
      broker_env_entries: env_entries
    )
  end

  def clear_broker_item_state(socket) do
    assign(socket,
      broker_ui_enabled?: false,
      broker_item_enabled: false,
      broker_placeholder: "",
      broker_credential_kind: "api_key",
      broker_inject_as: "header",
      broker_env_enabled_keys: [],
      broker_env_entries: []
    )
  end

  def toggle_item_broker(params, socket) do
    with true <- socket.assigns[:broker_ui_enabled?],
         id when not is_nil(id) <- socket.assigns.selected_vault_item_id,
         %{} = item <- ProjectVault.get_vault_item(id),
         socket <- VaultKey.ensure_vault_key_from_registry(socket),
         pw when is_binary(pw) and pw != "" <- socket.assigns.vault_password do
      enabled = truthy?(Map.get(params, "enabled", Map.get(params, "value")))

      case ProjectVault.set_vault_item_broker_enabled(item, enabled, %{}, pw) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign_broker_item_state(updated, pw)
           |> refresh_manifest(pw)
           |> assign(info: "Broker credential updated.", error: nil)}

        {:error, :license_local_broker_required} ->
          {:noreply, assign(socket, error: "Local Broker requires Personal Pro.", info: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Could not update Broker credential.", info: nil)}
      end
    else
      _ ->
        {:noreply,
         assign(socket, error: "Unlock the vault to configure Broker credentials.", info: nil)}
    end
  end

  def save_broker_placeholder(params, socket) do
    with true <- socket.assigns[:broker_ui_enabled?],
         id when not is_nil(id) <- socket.assigns.selected_vault_item_id,
         %{} = item <- ProjectVault.get_vault_item(id),
         socket <- VaultKey.ensure_vault_key_from_registry(socket),
         pw when is_binary(pw) and pw != "" <- socket.assigns.vault_password do
      opts = %{
        placeholder:
          case Map.get(params, "broker_placeholder", "") |> to_string() |> String.trim() do
            "" -> BrokerFrontmatter.default_placeholder(item.id)
            value -> value
          end,
        credential_kind: Map.get(params, "broker_credential_kind", "api_key") |> to_string(),
        inject_as: Map.get(params, "broker_inject_as", "header") |> to_string()
      }

      enabled = socket.assigns[:broker_item_enabled] == true

      case ProjectVault.set_vault_item_broker_enabled(item, enabled, opts, pw) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign_broker_item_state(updated, pw)
           |> refresh_manifest(pw)
           |> assign(info: "Broker credential saved.", error: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Could not save Broker credential.", info: nil)}
      end
    else
      _ ->
        {:noreply, assign(socket, error: "Unlock the vault to save Broker settings.", info: nil)}
    end
  end

  def toggle_env_broker_key(params, socket) do
    with true <- socket.assigns[:broker_ui_enabled?],
         id when not is_nil(id) <- socket.assigns.selected_vault_item_id,
         %{} = item <- ProjectVault.get_vault_item(id),
         socket <- VaultKey.ensure_vault_key_from_registry(socket),
         pw when is_binary(pw) and pw != "" <- socket.assigns.vault_password,
         key when is_binary(key) and key != "" <- Map.get(params, "key") |> to_string() do
      enabled = truthy?(Map.get(params, "enabled"))
      current = socket.assigns[:broker_env_enabled_keys] || []

      next_keys =
        if enabled do
          Enum.uniq([key | current])
        else
          Enum.reject(current, &(&1 == key))
        end

      case ProjectVault.set_vault_item_broker_enabled(
             item,
             true,
             %{env_enabled_keys: next_keys},
             pw
           ) do
        {:ok, updated} ->
          {:noreply,
           socket
           |> assign_broker_item_state(updated, pw)
           |> refresh_manifest(pw)
           |> assign(info: "Broker env key updated.", error: nil)}

        {:error, _} ->
          {:noreply, assign(socket, error: "Could not update env Broker key.", info: nil)}
      end
    else
      _ ->
        {:noreply,
         assign(socket, error: "Unlock the vault to configure env Broker keys.", info: nil)}
    end
  end

  defp env_broker_entries(item, password) do
    with {:ok, body} <- ProjectVault.decrypt_vault_item_body(item, password) do
      body
      |> Formatting.parse_env_entries()
      |> Enum.map(fn entry ->
        %{
          key: entry.key,
          placeholder: BrokerFrontmatter.placeholder_for_env_key(entry.key) || ""
        }
      end)
    else
      _ -> []
    end
  end

  defp refresh_manifest(socket, password) do
    folder_id = socket.assigns[:selected_folder_id]

    if socket.assigns[:broker_project_enabled] == true && folder_id do
      case ProjectVault.write_broker_scope_manifest_file(folder_id, password) do
        {:ok, _} ->
          push_event(socket, "broker_scope_changed", %{folder_id: folder_id})

        _ ->
          socket
      end
    else
      socket
    end
  end

  defp truthy?(value) when value in [true, "true", "1", "on", "yes"], do: true
  defp truthy?(_), do: false
end
