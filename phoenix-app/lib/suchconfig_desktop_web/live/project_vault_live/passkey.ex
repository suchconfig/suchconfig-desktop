defmodule SuchConfigDesktopWeb.ProjectVaultLive.Passkey do
  @moduledoc """
  Event handlers for Global Passkey lifecycle: show/cancel modal, request
  unlock, confirm native auth (first-time setup, unlock, and save
  continuations), and lock.

  Each handler takes `(params, socket)` and returns `{:noreply, socket}` so
  the LiveView module can dispatch to them directly from pattern-matched
  `handle_event/3` heads.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias Phoenix.PubSub
  alias SuchConfigDesktop.VaultSessionRegistry

  alias SuchConfigDesktopWeb.ProjectVaultLive.{
    LinkedSyncEvents,
    NoteEvents,
    VaultItemEvents,
    VaultKey
  }

  def show_modal(%{"purpose" => purpose}, socket) do
    normalized_purpose = if purpose in ["save", "unlock", "setup"], do: purpose, else: "setup"

    {:noreply,
     assign(socket,
       show_global_passkey_modal: true,
       global_passkey_input: "",
       global_passkey_purpose: normalized_purpose,
       error: nil,
       info: nil
     )}
  end

  def request_unlock(_params, socket) do
    if socket.assigns[:vault_session_id] do
      PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :request_unlock
      )
    end

    {:noreply, socket}
  end

  def cancel_modal(_params, socket) do
    pending = socket.assigns[:pending_unlock_action]

    reopen_link_project? =
      pending == :confirm_link_project and
        is_binary(socket.assigns[:link_project_scan_path]) and
        socket.assigns[:link_project_stage] == :preview

    {:noreply,
     assign(socket,
       show_global_passkey_modal: false,
       global_passkey_input: "",
       global_passkey_purpose: nil,
       pending_unlock_action: nil,
       show_link_project_modal: reopen_link_project? || socket.assigns[:show_link_project_modal]
     )}
  end

  def lock(_params, socket) do
    if socket.assigns[:vault_session_id] do
      VaultSessionRegistry.delete(socket.assigns.vault_session_id)

      PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :vault_locked
      )
    end

    {:noreply,
     assign(socket,
       global_passkey_unlocked: false,
       vault_password: "",
       show_global_passkey_modal: false,
       global_passkey_input: "",
       global_passkey_purpose: nil,
       pending_unlock_action: nil,
       decrypt_failed_wrong_key: false,
       pending_unlock_note_id: nil,
       pending_unlock_note_title: "",
       selected_vault_item_id: nil,
       editor_focus: :note,
       info: "Global Passkey locked.",
       error: nil
     )}
  end

  def confirm(_params, socket) do
    {:noreply,
     socket
     |> assign(error: nil, info: "Opening system authentication…")
     |> push_event("run_native_global_passkey_auth", %{})}
  end

  def native_available(params, socket) do
    {:noreply,
     assign(socket,
       native_passkey_supported: Map.get(params, "supported", false),
       native_passkey_platform: Map.get(params, "platform", "unknown"),
       native_passkey_provider: Map.get(params, "provider", "unknown")
     )}
  end

  def native_auth_failed(params, socket) do
    message = Map.get(params, "message", "Native Global Passkey authentication failed.")
    {:noreply, assign(socket, error: message, info: nil)}
  end

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
          security_mode: "global_passkey",
          show_global_passkey_modal: false,
          global_passkey_input: "",
          global_passkey_purpose: nil,
          decrypt_failed_wrong_key: false,
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
          cond do
            not is_nil(socket.assigns.pending_note_attrs) ->
              NoteEvents.persist_note(socket, socket.assigns.pending_note_attrs, key)

            is_binary(key) and String.trim(key) != "" and
                socket.assigns[:pending_unlock_action] == :new_vault_item ->
              socket = assign(socket, pending_unlock_action: nil)
              VaultItemEvents.new_vault_item(%{}, socket)

            is_binary(key) and String.trim(key) != "" and
                socket.assigns[:pending_unlock_action] == :save_vault_item ->
              socket = assign(socket, pending_unlock_action: nil)
              VaultItemEvents.save_vault_item_document(%{}, socket)

            is_binary(key) and String.trim(key) != "" and
                socket.assigns[:pending_unlock_action] == :confirm_link_project ->
              socket = assign(socket, pending_unlock_action: nil)
              VaultItemEvents.confirm_link_project(%{}, socket)

            is_binary(key) and String.trim(key) != "" and
                socket.assigns[:pending_unlock_action] == :sync_push ->
              socket = assign(socket, pending_unlock_action: nil)
              LinkedSyncEvents.sync_push_to_project(%{}, socket)

            is_binary(key) and String.trim(key) != "" and
                socket.assigns[:pending_unlock_action] == :sync_refresh ->
              socket = assign(socket, pending_unlock_action: nil)
              LinkedSyncEvents.sync_refresh_from_disk(%{}, socket)

            true ->
              {:noreply, socket}
          end

        "unlock" ->
          if first_time do
            {:noreply, socket}
          else
            confirm_global_unlock(socket, key)
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

    unlocked = is_binary(key) and String.trim(key) != ""

    {:noreply,
     assign(socket,
       global_passkey_unlocked: unlocked,
       vault_password: if(unlocked, do: key, else: ""),
       error: nil,
       info: if(unlocked, do: socket.assigns[:info], else: nil)
     )}
  end

  def apply_vault_locked_state(socket) do
    {:noreply,
     assign(socket,
       global_passkey_unlocked: false,
       vault_password: "",
       show_global_passkey_modal: false,
       global_passkey_input: "",
       global_passkey_purpose: nil,
       pending_unlock_action: nil,
       show_new_folder_modal: false,
       decrypt_failed_wrong_key: false,
       pending_unlock_note_id: nil,
       pending_unlock_note_title: "",
       selected_vault_item_id: nil,
       editor_focus: :note,
       info: "Global Passkey locked.",
       error: nil,
       new_note_form_highlight: false,
       show_new_note_modal: false
     )}
  end

  def confirm_global_unlock(socket, passkey) do
    alias SuchConfigDesktop.ProjectVault
    alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

    note_id = socket.assigns.pending_unlock_note_id

    if is_nil(note_id) do
      {:noreply, assign(socket, error: "No note selected to unlock.", info: nil)}
    else
      note = ProjectVault.get_note!(note_id)

      case VaultKey.decrypt_note_content(note, passkey) do
        {:ok, raw_content} ->
          {:noreply,
           assign(socket,
             selected_note_id: note.id,
             note_unlocked: true,
             note_category: Formatting.normalize_note_type(note.note_type),
             vault_item_kind: Formatting.normalize_note_type(note.note_type),
             note_title: note.title,
             note_raw_content: raw_content,
             pending_unlock_note_id: nil,
             pending_unlock_note_title: "",
             show_global_passkey_modal: false,
             security_mode: "global_passkey",
             copy_all_copied: false,
             env_var_value_copied: %{},
             env_var_all_copied: %{},
             global_passkey_unlocked: true,
             vault_password: passkey,
             decrypt_failed_wrong_key: false,
             error: nil,
             info: "Global Passkey unlock successful.",
             new_note_form_highlight: false
           )}

        {:error, _} ->
          {:noreply,
           assign(socket,
             selected_note_id: note.id,
             note_unlocked: false,
             note_category: Formatting.normalize_note_type(note.note_type),
             vault_item_kind: Formatting.normalize_note_type(note.note_type),
             note_title: note.title,
             note_raw_content: "",
             show_global_passkey_modal: false,
             pending_unlock_note_id: note.id,
             pending_unlock_note_title: note.title,
             decrypt_failed_wrong_key: true,
             error: "This note could not be decrypted with the current passkey.",
             info: nil,
             new_note_form_highlight: false
           )}
      end
    end
  end

  def set_security_mode(_params, socket) do
    {:noreply,
     assign(socket,
       security_mode: "global_passkey",
       global_passkey_unlocked: socket.assigns.global_passkey_unlocked,
       vault_password: socket.assigns.vault_password,
       show_global_passkey_modal: false,
       global_passkey_input: "",
       global_passkey_purpose: nil,
       info: nil,
       error: nil
     )}
  end

  def set_vault_password(%{"vault_password" => vault_password}, socket) do
    {:noreply, assign(socket, vault_password: vault_password)}
  end
end
