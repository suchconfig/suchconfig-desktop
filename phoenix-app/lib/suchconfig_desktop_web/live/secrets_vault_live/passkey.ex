defmodule SuchConfigDesktopWeb.SecretsVaultLive.Passkey do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Phoenix.PubSub
  alias SuchConfigDesktop.VaultSessionRegistry
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey
  alias SuchConfigDesktopWeb.SecretsVaultLive.EntryEvents
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData

  defdelegate show_modal(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  defdelegate cancel_modal(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  defdelegate lock(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  defdelegate confirm(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  defdelegate request_unlock(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  defdelegate native_available(params, socket), to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey

  defdelegate native_auth_failed(params, socket),
    to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey

  defdelegate set_vault_password(params, socket),
    to: SuchConfigDesktopWeb.ProjectVaultLive.Passkey

  def native_authenticated(params, socket) do
    purpose = socket.assigns.global_passkey_purpose
    first_time = Map.get(params, "first_time") == true
    passkey = Map.get(params, "passkey") || Map.get(params, "unwrapped_key")

    key =
      if first_time do
        VaultKey.new_session_vault_key()
      else
        if is_binary(passkey) and String.trim(passkey) != "", do: passkey, else: nil
      end

    if is_binary(key) and String.trim(key) != "" do
      socket =
        assign(socket,
          global_passkey_unlocked: true,
          vault_password: key,
          show_global_passkey_modal: false,
          global_passkey_input: "",
          global_passkey_purpose: nil,
          error: nil,
          info: if(first_time, do: "Session unlocked.", else: "Native authentication successful.")
        )

      socket =
        if first_time do
          push_event(socket, "store_vault_key", %{
            key_id: VaultKey.vault_key_id(),
            wrapped_key: key
          })
        else
          socket
        end

      case purpose do
        "save" ->
          action = socket.assigns[:pending_unlock_action]

          socket = assign(socket, pending_unlock_action: nil)

          case action do
            :save_item -> EntryEvents.save_item(%{}, socket)
            :new_item -> EntryEvents.new_item(%{}, socket)
            _ -> {:noreply, socket}
          end

        "unlock" ->
          if first_time do
            {:noreply, reload_after_unlock(socket, key)}
          else
            {:noreply, reload_after_unlock(socket, key)}
          end

        _ ->
          {:noreply, socket}
      end
    else
      {:noreply,
       assign(socket,
         error: "Native authentication succeeded but no passkey was returned.",
         info: nil
       )}
    end
  end

  def apply_vault_unlocked(socket) do
    key =
      if socket.assigns[:vault_session_id],
        do: VaultSessionRegistry.get(socket.assigns.vault_session_id) || "",
        else: ""

    reload_after_unlock(socket, key)
  end

  def apply_vault_locked_state(socket) do
    {:noreply,
     assign(socket,
       global_passkey_unlocked: false,
       vault_password: "",
       show_global_passkey_modal: false,
       global_passkey_purpose: nil,
       pending_unlock_action: nil,
       show_new_entry_modal: false,
       selected_item_id: nil,
       secret_body: "",
       username: "",
       url: "",
       public_key: "",
       fingerprint: "",
       show_secret: false,
       info: "Global Passkey locked.",
       error: nil
     )}
  end

  defp reload_after_unlock(socket, key) do
    _ = SuchConfigDesktop.SecretsVault.ensure_unassociated_folder()

    folders = SuchConfigDesktop.SecretsVault.list_folders()

    folder_id =
      case socket.assigns.selected_folder_id do
        :all -> :all
        nil -> List.first(folders) && List.first(folders).id
        id -> id
      end

    query_folder_id =
      SuchConfigDesktopWeb.SecretsVaultLive.Formatting.items_query_folder_id(folder_id)

    items =
      if folder_id == :all or is_integer(folder_id) do
        SuchConfigDesktop.SecretsVault.list_items(query_folder_id)
      else
        []
      end

    assign(socket,
      folders: folders,
      selected_folder_id: folder_id,
      items: items,
      global_passkey_unlocked: true,
      vault_password: key,
      info: "Global Passkey unlock successful.",
      error: nil
    )
    |> ViewData.assign_view_data(refresh_all_items: true)
  end

  def subscribe_vault_lock(socket) do
    if socket.assigns[:vault_session_id] do
      PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{socket.assigns.vault_session_id}")
    end

    socket
  end

  def restore_session_key(socket, session) do
    vault_session_id = session["vault_session_id"]

    vault_key =
      if vault_session_id,
        do: VaultSessionRegistry.get(vault_session_id),
        else: nil

    key = if is_binary(vault_key) and String.trim(vault_key) != "", do: vault_key, else: ""
    unlocked = key != ""

    assign(socket,
      vault_session_id: vault_session_id,
      vault_password: key,
      global_passkey_unlocked: unlocked
    )
  end
end
