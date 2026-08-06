defmodule SuchConfigDesktopWeb.AppLive do
  use SuchConfigDesktopWeb, :live_view

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktopWeb.Components.ProjectVault.Modals, as: ProjectVaultModals
  alias SuchConfigDesktopWeb.Components.ProjectVault.ProjectsGrid
  alias SuchConfigDesktopWeb.ProjectsLive.FolderEvents
  alias SuchConfigDesktopWeb.ProjectsLive.Formatting, as: ProjectsFormatting
  alias SuchConfigDesktopWeb.SecretsVaultLive.Generator
  alias SuchConfigDesktopWeb.TrustedFolderEvents
  alias SuchConfigDesktopWeb.P2pLanSyncEvents

  @vault_key_id "suchconfig.project_manager.vault"

  def mount(_params, session, socket) do
    vault_session_id = session["vault_session_id"]

    key =
      if vault_session_id,
        do: SuchConfigDesktop.VaultSessionRegistry.get(vault_session_id),
        else: nil

    has_key = is_binary(key) and String.trim(key) != ""

    show_unlock_overlay = not has_key
    vault_skipped = false
    vault_unlocked = has_key

    if vault_session_id do
      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{vault_session_id}")
    end

    Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, Generator.topic())

    vault_item_ui_enabled? =
      ProjectVault.feature_enabled?() and ProjectVault.vault_item_crdt_persistence_enabled?()

    folders = ProjectVault.list_project_folders()

    socket =
      socket
      |> assign(
        current_page: :home,
        page_title: "SuchConfig",
        navigation_items: navigation_items(vault_unlocked),
        show_unlock_overlay: show_unlock_overlay,
        vault_skipped: vault_skipped,
        vault_session_id: vault_session_id,
        vault_key_id: @vault_key_id,
        vault_unlock_error: nil,
        vault_key_pending_store: false,
        vault_unlocked: vault_unlocked,
        command_palette_open: false,
        command_palette_cursor: 0,
        selected_project_id: nil,
        selected_project_name: nil,
        vault_activity_visible: false,
        vault_item_ui_enabled?: vault_item_ui_enabled?,
        folders: folders,
        expanded_projects: ProjectsFormatting.default_expanded_projects(folders),
        show_edit_folder_modal: false,
        editing_folder_id: nil,
        edit_folder_name: "",
        edit_folder_delete_confirm: false,
        show_new_folder_modal: false,
        folder_name: "",
        folder_description: "",
        folder_tags: "",
        new_folder_link_path: nil,
        new_folder_link_stage: :idle,
        new_folder_link_error: nil,
        new_folder_run_sentinel: false,
        pending_link_project_path: nil,
        pending_link_project_run_sentinel: false,
        project_info: nil,
        project_error: nil
      )
      |> ProjectsFormatting.assign_project_entries()
      |> assign(Generator.default_assigns())
      |> assign(TrustedFolderEvents.default_assigns())
      |> TrustedFolderEvents.on_mount_connected()

    {:ok, socket}
  end

  def handle_event("open_command_palette", _params, socket) do
    {:noreply,
     assign(socket,
       command_palette_open: true,
       command_palette_cursor: 0
     )}
  end

  def handle_event("close_command_palette", _params, socket) do
    {:noreply, close_command_palette_assigns(socket)}
  end

  def handle_event("command_palette_hover", %{"index" => index}, socket) do
    {:noreply, assign(socket, command_palette_cursor: parse_index(index))}
  end

  def handle_event("command_palette_hover", _params, socket), do: {:noreply, socket}

  def handle_event("command_palette_key", %{"key" => key}, socket) do
    handle_palette_key(socket, key)
  end

  def handle_event("command_palette_action", %{"id" => id}, socket) when is_binary(id) do
    socket =
      socket
      |> close_command_palette_assigns()
      |> run_palette_command(id)

    {:noreply, socket}
  end

  def handle_event("command_palette_action", _params, socket), do: {:noreply, socket}

  def handle_event("keyboard_chord", %{"id" => id}, socket) when is_binary(id) do
    if socket.assigns.command_palette_open do
      socket =
        socket
        |> close_command_palette_assigns()
        |> run_palette_command(id)

      {:noreply, socket}
    else
      {:noreply, run_palette_command(socket, id)}
    end
  end

  def handle_event("keyboard_chord", _params, socket), do: {:noreply, socket}

  def handle_event("trusted_folder_status", params, socket) do
    {:noreply, TrustedFolderEvents.apply_status(socket, params)}
  end

  def handle_event("trusted_folder_setup_complete", params, socket) do
    {:noreply, TrustedFolderEvents.handle_setup_complete(socket, params)}
  end

  def handle_event("trusted_folder_synced", params, socket) do
    {:noreply, TrustedFolderEvents.handle_synced(socket, params)}
  end

  def handle_event("trusted_folder_request_initial_export", params, socket) do
    {:noreply, TrustedFolderEvents.handle_request_initial_export(socket, params)}
  end

  def handle_event("trusted_folder_import_snapshot", params, socket) do
    {:noreply, TrustedFolderEvents.handle_import_snapshot(socket, params)}
  end

  def handle_event("begin_trusted_folder_setup", _params, socket) do
    {:noreply, TrustedFolderEvents.begin_setup(socket)}
  end

  def handle_event("dismiss_trusted_folder_modal", _params, socket) do
    {:noreply, TrustedFolderEvents.close_modal(socket)}
  end

  def handle_event("trusted_folder_setup_done", %{"path" => path}, socket) do
    {:noreply,
     socket
     |> TrustedFolderEvents.apply_status(%{
       "trusted_folder_path" => path,
       "watcher_running" => true
     })
     |> assign(
       trusted_folder_modal_busy: false,
       show_trusted_folder_modal: false,
       trusted_folder_changing_path: false
     )}
  end

  def handle_event("trusted_folder_setup_failed", %{"message" => message}, socket) do
    {:noreply,
     assign(socket,
       trusted_folder_modal_busy: false,
       trusted_folder_modal_error: message
     )}
  end

  def handle_event("trusted_folder_setup_failed", _params, socket) do
    {:noreply,
     assign(socket,
       trusted_folder_modal_busy: false,
       trusted_folder_modal_error: "Trusted Folder setup failed."
     )}
  end

  def handle_event("open_trusted_folder_setup", _params, socket) do
    {:noreply, TrustedFolderEvents.open_modal(socket)}
  end

  def handle_event("open_trusted_folder_change", _params, socket) do
    {:noreply, TrustedFolderEvents.open_change_modal(socket)}
  end

  def handle_event("force_sync_trusted_folder_ui", _params, socket) do
    {:noreply, TrustedFolderEvents.request_sync_now(socket)}
  end

  def handle_event("trusted_folder_sync_failed", params, socket) do
    {:noreply, TrustedFolderEvents.handle_sync_failed(socket, params)}
  end

  def handle_event("trusted_folder_verify_result", params, socket) do
    {:noreply, TrustedFolderEvents.handle_verify_result(socket, params)}
  end

  def handle_event("p2p_lan_discovery_update", params, socket) do
    P2pLanSyncEvents.forward_to_settings({:p2p_lan_discovery_update, params})
    {:noreply, socket}
  end

  def handle_event("p2p_lan_handoff_bundle", params, socket) do
    {:noreply, P2pLanSyncEvents.handle_handoff_bundle(socket, params)}
  end

  def handle_event("p2p_handoff_ready_for_bundles", params, socket) do
    P2pLanSyncEvents.forward_to_settings({:p2p_handoff_ready_for_bundles, params})
    {:noreply, socket}
  end

  def handle_event("p2p_lan_handoff_complete", params, socket) do
    P2pLanSyncEvents.forward_to_settings({:p2p_lan_handoff_complete, params})
    {:noreply, socket}
  end

  def handle_event("p2p_lan_delta_received", params, socket) do
    {:noreply, P2pLanSyncEvents.handle_delta_received(socket, params)}
  end

  def handle_event("p2p_lan_sync_error", params, socket) do
    P2pLanSyncEvents.forward_to_settings({:p2p_lan_sync_error, params})
    {:noreply, socket}
  end

  def handle_event("open_generator_drawer", params, socket) do
    {:noreply, Generator.open_from_params(params, socket)}
  end

  def handle_event("close_generator_drawer", _params, socket) do
    {:noreply, Generator.close(socket)}
  end

  def handle_event("roll_generator", _params, socket) do
    {:noreply, Generator.roll(socket)}
  end

  def handle_event("set_generator_mode", %{"mode" => mode}, socket) do
    if mode in Generator.modes() do
      {:noreply, Generator.set_mode(socket, mode)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("set_generator_username_form", params, socket) do
    {:noreply, Generator.set_username_form(socket, params)}
  end

  def handle_event("set_generator_length", params, socket) do
    {:noreply, Generator.set_length(socket, Generator.parse_length_from_params(params))}
  end

  def handle_event("toggle_generator_opt", %{"opt" => opt, "on" => on}, socket) do
    {:noreply, Generator.toggle_opt(socket, opt, on == "true")}
  end

  def handle_event("copy_generator", _params, socket) do
    {:noreply, copy_generator_feedback(socket)}
  end

  def handle_event("set_generator_password", _params, socket) do
    value = socket.assigns.generator_value
    strength = socket.assigns.generator_strength_level

    if secrets_vault_enabled?() and value != "" do
      Generator.broadcast_apply(value, strength)
    end

    {:noreply, Generator.close(socket)}
  end

  def handle_event("set_generator_username", _params, socket) do
    value = socket.assigns.generator_value

    if secrets_vault_enabled?() and value != "" do
      Generator.broadcast_apply_username(value)
    end

    {:noreply, Generator.close(socket)}
  end

  def handle_event("navigate", %{"page" => page}, socket) do
    page_atom = String.to_existing_atom(page)

    socket =
      if page_atom == :project_vault do
        navigate_to_project_vault(socket)
      else
        socket |> assign(current_page: page_atom) |> maybe_notify_page_visible(page_atom)
      end

    {:noreply, socket}
  end

  def handle_event("open_new_folder_modal", params, socket),
    do: FolderEvents.open_new_folder_modal(params, socket)

  def handle_event("cancel_new_folder_modal", params, socket),
    do: FolderEvents.cancel_new_folder_modal(params, socket)

  def handle_event("new_folder_form_change", params, socket),
    do: FolderEvents.new_folder_form_change(params, socket)

  def handle_event("create_folder", params, socket),
    do: FolderEvents.create(params, socket)

  def handle_event("folder_selected", %{"path" => path}, socket) do
    if socket.assigns[:show_new_folder_modal] do
      FolderEvents.folder_selected_for_new_project(path, socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("folder_select_error", params, socket) do
    if socket.assigns[:show_new_folder_modal] do
      message =
        params["error"] || params["message"] || params[:error] || params[:message] ||
          "Failed to select folder"

      FolderEvents.folder_select_error_for_new_project(to_string(message), socket)
    else
      {:noreply, socket}
    end
  end

  def handle_event("open_edit_folder", params, socket),
    do: FolderEvents.open_edit(params, socket)

  def handle_event("cancel_edit_folder", params, socket),
    do: FolderEvents.cancel_edit(params, socket)

  def handle_event("edit_folder_input", params, socket),
    do: FolderEvents.edit_folder_input(params, socket)

  def handle_event("save_edit_folder", params, socket),
    do: FolderEvents.save_edit(params, socket)

  def handle_event("delete_folder", params, socket),
    do: FolderEvents.delete_editing(params, socket)

  def handle_event("request_delete_folder", params, socket),
    do: FolderEvents.request_delete_folder(params, socket)

  def handle_event("cancel_delete_folder_confirm", params, socket),
    do: FolderEvents.cancel_delete_folder_confirm(params, socket)

  def handle_event("toggle_project_contents", %{"id" => id}, socket) do
    folder_id = String.to_integer(id)
    expanded = socket.assigns.expanded_projects
    next = Map.update(expanded, folder_id, true, &(!&1))
    {:noreply, assign(socket, expanded_projects: next)}
  end

  def handle_event("toggle_project_contents", _params, socket), do: {:noreply, socket}

  def handle_event(
        "toggle_vault_activity",
        _params,
        %{assigns: %{current_page: :projects}} = socket
      ) do
    visible = !socket.assigns.vault_activity_visible

    case List.first(socket.assigns.folders) do
      %{id: id, name: name} ->
        {:noreply,
         assign(socket,
           current_page: :project_vault,
           selected_project_id: id,
           selected_project_name: name,
           vault_activity_visible: visible
         )}

      _ ->
        {:noreply, assign(socket, vault_activity_visible: visible)}
    end
  end

  def handle_event("open_project", %{"id" => id}, socket) do
    folder_id = String.to_integer(id)
    folder = Enum.find(socket.assigns.folders, &(&1.id == folder_id))

    {:noreply,
     assign(socket,
       current_page: :project_vault,
       selected_project_id: folder_id,
       selected_project_name: folder && folder.name,
       vault_activity_visible: false
     )}
  end

  def handle_event("open_project", _params, socket), do: {:noreply, socket}

  def handle_event("proceed_without_unlock", _params, socket) do
    {:noreply,
     socket
     |> assign(
       show_unlock_overlay: false,
       vault_skipped: true,
       vault_unlocked: false,
       navigation_items: navigation_items(false)
     )}
  end

  def handle_event("native_global_passkey_available", _params, socket) do
    {:noreply, socket}
  end

  def handle_event("lock_global_passkey_from_settings", _params, socket) do
    socket =
      if socket.assigns[:vault_session_id] do
        SuchConfigDesktop.VaultSessionRegistry.delete(socket.assigns.vault_session_id)

        Phoenix.PubSub.broadcast(
          SuchConfigDesktop.PubSub,
          "vault:#{socket.assigns.vault_session_id}",
          :vault_locked_no_overlay
        )

        socket
      else
        socket
      end

    {:noreply,
     assign(socket,
       show_unlock_overlay: false,
       vault_unlocked: false,
       navigation_items: navigation_items(false)
     )}
  end

  def handle_event("request_unlock", _params, socket) do
    {:noreply, push_event(socket, "run_native_global_passkey_auth", %{})}
  end

  def handle_event("confirm_global_passkey", _params, socket) do
    {:noreply, assign(socket, vault_unlock_error: nil)}
  end

  def handle_event("native_global_passkey_authenticated", params, socket) do
    first_time = Map.get(params, "first_time") == true
    passkey = Map.get(params, "passkey") || Map.get(params, "unwrapped_key")

    key =
      if first_time do
        new_session_vault_key()
      else
        if is_binary(passkey) and String.trim(passkey) != "", do: passkey, else: nil
      end

    if is_binary(key) and String.trim(key) != "" and socket.assigns.vault_session_id do
      SuchConfigDesktop.VaultSessionRegistry.put(socket.assigns.vault_session_id, key)
      SuchConfigDesktop.VaultKeyStore.put(@vault_key_id, key)

      socket =
        if first_time do
          socket
          |> assign(vault_unlock_error: nil, vault_key_pending_store: true)
          |> push_event("store_vault_key", %{key_id: @vault_key_id, wrapped_key: key})
        else
          socket
          |> assign(
            show_unlock_overlay: false,
            vault_unlock_error: nil,
            vault_unlocked: true,
            navigation_items: navigation_items(true)
          )
          |> push_event("store_vault_key", %{key_id: @vault_key_id, wrapped_key: key})
        end

      socket =
        unless first_time do
          if connected?(socket) do
            Phoenix.PubSub.broadcast(
              SuchConfigDesktop.PubSub,
              "vault:#{socket.assigns.vault_session_id}",
              :vault_unlocked
            )
          end

          push_event(socket, "clear_vault_skipped_cookie", %{})
        else
          socket
        end

      {:noreply, socket}
    else
      {:noreply,
       assign(socket,
         vault_unlock_error: "Authentication succeeded but no passkey was returned."
       )}
    end
  end

  def handle_event("native_global_passkey_auth_failed", params, socket) do
    message = Map.get(params, "message", "Authentication failed.")
    {:noreply, assign(socket, vault_unlock_error: message)}
  end

  def handle_event("vault_key_not_found", _params, socket) do
    key = SuchConfigDesktop.VaultKeyStore.get(@vault_key_id)

    socket =
      if is_binary(key) and String.trim(key) != "" do
        push_event(socket, "vault_key_from_db", %{key: key})
      else
        socket
        |> assign(vault_unlock_error: nil)
        |> push_event("vault_key_from_db", %{})
      end

    {:noreply, socket}
  end

  def handle_event("vault_key_stored", params, socket) do
    ok = params["ok"] == true
    message = params["message"] || ""

    socket =
      socket
      |> assign(vault_key_pending_store: false)

    socket =
      if ok do
        if connected?(socket) do
          Phoenix.PubSub.broadcast(
            SuchConfigDesktop.PubSub,
            "vault:#{socket.assigns.vault_session_id}",
            :vault_unlocked
          )
        end

        socket
        |> assign(
          show_unlock_overlay: false,
          vault_unlock_error: nil,
          vault_unlocked: true,
          navigation_items: navigation_items(true)
        )
        |> push_event("clear_vault_skipped_cookie", %{})
        |> TrustedFolderEvents.push_full_sync_if_ready()
      else
        assign(socket,
          vault_unlock_error:
            "Could not save key to Keychain. " <> (message || "Please try again.")
        )
      end

    {:noreply, socket}
  end

  def handle_info({:parent, :navigate, page}, socket) do
    {:noreply,
     socket
     |> assign(current_page: page)
     |> maybe_notify_page_visible(page)}
  end

  def handle_info(:refresh_project_entries, socket) do
    {:noreply, ProjectsFormatting.refresh_project_entries(socket)}
  end

  def handle_info({:generator_open, :secrets_entry, opts}, socket) do
    socket =
      socket
      |> assign(current_page: :secrets_vault)
      |> maybe_notify_page_visible(:secrets_vault)
      |> Generator.open(:secrets_entry, opts)

    {:noreply, socket}
  end

  def handle_info({:generator_open, :secrets_entry}, socket) do
    handle_info({:generator_open, :secrets_entry, []}, socket)
  end

  def handle_info({:generator_open, :standalone, opts}, socket) do
    {:noreply, Generator.open(socket, :standalone, opts)}
  end

  def handle_info({:generator_open, :standalone}, socket) do
    {:noreply, Generator.open(socket, :standalone)}
  end

  def handle_info({:generator_apply_username, _value}, socket) do
    {:noreply, socket}
  end

  def handle_info(:generator_open, socket) do
    {:noreply, Generator.open(socket, :standalone)}
  end

  def handle_info({:generator_apply, _value, _strength}, socket) do
    {:noreply, socket}
  end

  def handle_info(:clear_generator_copied, socket) do
    {:noreply, assign(socket, generator_copied: false)}
  end

  def handle_info(:vault_unlocked, socket) do
    key =
      if socket.assigns[:vault_session_id],
        do: SuchConfigDesktop.VaultSessionRegistry.get(socket.assigns.vault_session_id),
        else: nil

    has_key = is_binary(key) and String.trim(key) != ""

    {:noreply,
     socket
     |> assign(
       vault_unlocked: has_key,
       navigation_items: navigation_items(has_key),
       show_unlock_overlay: false,
       vault_unlock_error: nil
     )
     |> TrustedFolderEvents.on_mount_connected()
     |> TrustedFolderEvents.push_full_sync_if_ready()}
  end

  def handle_info({:trusted_folder_status, params}, socket) do
    {:noreply, TrustedFolderEvents.apply_status(socket, params)}
  end

  def handle_info(:vault_locked, socket) do
    {:noreply,
     assign(socket,
       show_unlock_overlay: true,
       vault_unlocked: false,
       navigation_items: navigation_items(false)
     )}
  end

  def handle_info(:do_lock_global_passkey, socket) do
    socket =
      if socket.assigns[:vault_session_id] do
        SuchConfigDesktop.VaultSessionRegistry.delete(socket.assigns.vault_session_id)

        Phoenix.PubSub.broadcast(
          SuchConfigDesktop.PubSub,
          "vault:#{socket.assigns.vault_session_id}",
          :vault_locked_no_overlay
        )

        socket
      else
        socket
      end

    {:noreply,
     assign(socket,
       show_unlock_overlay: false,
       vault_unlocked: false,
       navigation_items: navigation_items(false)
     )}
  end

  def handle_info(:vault_locked_no_overlay, socket) do
    {:noreply, socket}
  end

  def handle_info(:request_unlock, socket) do
    {:noreply, push_event(socket, "run_native_global_passkey_auth", %{})}
  end

  def handle_info(:trusted_folder_sync_now, socket) do
    {:noreply, TrustedFolderEvents.request_sync_now(socket)}
  end

  def handle_info(:trusted_folder_verify_integrity, socket) do
    {:noreply, TrustedFolderEvents.request_verify_integrity(socket)}
  end

  def handle_info(:open_trusted_folder_setup, socket) do
    {:noreply, TrustedFolderEvents.open_modal(socket)}
  end

  def handle_info(:open_trusted_folder_change, socket) do
    {:noreply, TrustedFolderEvents.open_change_modal(socket)}
  end

  def handle_info({:trusted_folder_sync, vault}, socket) when vault in ["projects", "secrets"] do
    socket =
      if socket.assigns[:vault_unlocked] == true do
        TrustedFolderEvents.push_single_vault_sync(socket, vault)
        |> P2pLanSyncEvents.push_vault_deltas(vault)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:p2p_lan_sync, vault}, socket) when vault in ["projects", "secrets"] do
    {:noreply, P2pLanSyncEvents.push_vault_deltas(socket, vault)}
  end

  def handle_info({:p2p_lan_sync, _}, socket), do: {:noreply, socket}

  def handle_info({:trusted_folder_sync, _}, socket), do: {:noreply, socket}

  def handle_info({:palette_project_vault, message}, socket)
      when message in [:open_archive_export, :open_archive_import] do
    broadcast_project_vault(socket, message)
    {:noreply, socket}
  end

  def handle_info(:clear_pending_link_project, socket) do
    {:noreply,
     assign(socket,
       pending_link_project_path: nil,
       pending_link_project_run_sentinel: false
     )}
  end

  defp new_session_vault_key do
    32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  def render(assigns) do
    ~H"""
    <div id="app-live-root" class="contents">
      <div id="app-hook-vault-key-store" phx-hook="VaultKeyStore" class="hidden" aria-hidden="true">
      </div>
      <div
        id="app-hook-command-palette-hotkey"
        phx-hook="CommandPaletteHotkey"
        class="hidden"
        aria-hidden="true"
      >
      </div>
      <div
        id="app-hook-trusted-folder-sync"
        phx-hook="TrustedFolderSync"
        class="hidden"
        aria-hidden="true"
      >
      </div>
      <div
        id="app-hook-p2p-lan-sync"
        phx-hook="P2pLanSync"
        class="hidden"
        aria-hidden="true"
      >
      </div>
      <div
        id="app-hook-global-passkey-native"
        phx-hook="GlobalPasskeyNative"
        data-vault-key-id={@vault_key_id}
        data-native-passkey-reason="Unlock your vault."
        class="hidden"
        aria-hidden="true"
      >
      </div>
      <.trusted_folder_modal
        show={@show_trusted_folder_modal}
        busy={@trusted_folder_modal_busy}
        error={@trusted_folder_modal_error}
        changing={@trusted_folder_changing_path}
      />
      <.unlock_modal
        show={@show_unlock_overlay}
        vault_key_id={@vault_key_id}
        vault_unlock_error={@vault_unlock_error}
        vault_key_pending_store={@vault_key_pending_store}
      />
      <Layouts.app
        flash={@flash}
        current_page={@current_page}
        navigation_items={@navigation_items}
        vault_unlocked={@vault_unlocked}
        main_class="px-0"
      >
        <div class="shell flex-1 min-h-0" data-nav="rail">
          <.rail
            current_page={@current_page}
            secrets_vault_enabled={secrets_vault_enabled?()}
          />
          <main class="frame flex-1 min-h-0 flex flex-col">
            <.topbar
              current_page={@current_page}
              vault_unlocked={@vault_unlocked}
              project_name={@selected_project_name}
              trusted_folder_display_path={@trusted_folder_display_path}
              trusted_folder_synced={@trusted_folder_synced}
              trusted_folder_watcher_running={@trusted_folder_watcher_running}
            />
            <div class={[
              "flex-1 min-h-0",
              vault_page?(@current_page) && "frame-inner frame-inner--full",
              !vault_page?(@current_page) && "frame-inner"
            ]}>
              <div class={["space-y-6", @current_page != :home && "hidden"]}>
                <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
                  <div class="card">
                    <h4>Project Vault</h4>
                    <p class="muted" style="margin-bottom: 16px">
                      Notes, secrets, rules, and project files with local-first CRDT merge
                    </p>
                    <button
                      type="button"
                      phx-click="navigate"
                      phx-value-page="projects"
                      phx-throttle="300"
                      class="btn sm ghost"
                    >
                      Open Projects →
                    </button>
                  </div>

                  <div class="card">
                    <h4>Secrets Vault</h4>
                    <p class="muted" style="margin-bottom: 16px">
                      Passwords, API keys, and credentials with local-first CRDT storage.
                    </p>
                    <button
                      :if={secrets_vault_enabled?()}
                      type="button"
                      phx-click="navigate"
                      phx-value-page="secrets_vault"
                      phx-throttle="300"
                      class="btn sm ghost"
                    >
                      Open Secrets Vault →
                    </button>
                  </div>
                </div>
              </div>
              <div :if={@current_page == :projects} class="projects-shell">
                <ProjectsGrid.projects_grid
                  project_entries={@project_entries}
                  expanded_projects={@expanded_projects}
                  vault_activity_visible={@vault_activity_visible}
                  total_item_count={@total_item_count}
                  vault_unlocked={@vault_unlocked}
                />
                <p :if={@project_info} class="vault-flash ok">{@project_info}</p>
                <p :if={@project_error} class="vault-flash err">{@project_error}</p>
                <ProjectVaultModals.edit_folder_modal
                  show={@show_edit_folder_modal}
                  edit_folder_name={@edit_folder_name}
                  edit_folder_delete_confirm={@edit_folder_delete_confirm}
                />
              </div>
              <div class={["h-full min-h-0 w-full", @current_page != :project_vault && "hidden"]}>
                {live_render(@socket, SuchConfigDesktopWeb.ProjectVaultLive,
                  id: project_vault_live_id(@selected_project_id, @vault_activity_visible),
                  session: %{
                    "vault_session_id" => @vault_session_id,
                    "embedded" => true,
                    "selected_folder_id" => @selected_project_id,
                    "vault_activity_visible" => @vault_activity_visible,
                    "pending_link_project_path" => @pending_link_project_path,
                    "pending_link_project_run_sentinel" => @pending_link_project_run_sentinel
                  }
                )}
              </div>
              <div
                :if={secrets_vault_enabled?()}
                class={["h-full min-h-0 w-full", @current_page != :secrets_vault && "hidden"]}
              >
                {live_render(@socket, SuchConfigDesktopWeb.SecretsVaultLive,
                  id: "secrets_vault",
                  session: %{
                    "vault_session_id" => @vault_session_id,
                    "embedded" => true
                  }
                )}
              </div>
              <div class={["h-full", @current_page != :about && "hidden"]}>
                {live_render(@socket, SuchConfigDesktopWeb.AboutLive, id: "about")}
              </div>
              <div class={["h-full min-h-0", @current_page != :docs && "hidden"]}>
                {live_render(@socket, SuchConfigDesktopWeb.DocsLive, id: "docs")}
              </div>
              <div class={["h-full", @current_page != :settings && "hidden"]}>
                {live_render(@socket, SuchConfigDesktopWeb.SettingsLive,
                  id: "settings",
                  session: %{
                    "vault_session_id" => @vault_session_id,
                    "vault_unlocked" => @vault_unlocked
                  }
                )}
              </div>
              <div class={[
                "text-center py-12",
                @current_page in [
                  :home,
                  :projects,
                  :project_vault,
                  :secrets_vault,
                  :about,
                  :docs,
                  :settings
                ] &&
                  "hidden"
              ]}>
                <h3 class="text-lg font-medium">Page not found</h3>
                <p class="muted">This page is not available yet.</p>
              </div>
            </div>
          </main>
        </div>
        <.command_palette
          open={@command_palette_open}
          cursor={@command_palette_cursor}
          secrets_vault_enabled={secrets_vault_enabled?()}
        />
      </Layouts.app>
      <.generator_drawer
        open={@show_generator_drawer}
        value={@generator_value}
        mode={@generator_mode}
        length={@generator_length}
        length_min={Generator.length_min(@generator_mode, @generator_opts)}
        length_max={Generator.length_max(@generator_mode, @generator_opts)}
        opts={@generator_opts}
        strength_level={@generator_strength_level}
        strength_label={@generator_strength_label}
        recent={@generator_recent}
        context={@generator_context}
        copied={@generator_copied}
        passphrase_words={Generator.passphrase_word_count(@generator_length)}
      />
      <ProjectVaultModals.new_folder_modal
        show={@show_new_folder_modal}
        folder_name={@folder_name}
        folder_description={@folder_description}
        folder_tags={@folder_tags}
        link_stage={@new_folder_link_stage}
        link_path={@new_folder_link_path}
        link_error={@new_folder_link_error}
        error={@project_error}
        run_sentinel_scan={@new_folder_run_sentinel}
        pro_plan?={SuchConfigDesktop.ProjectVault.security_sentinel_license_enabled?()}
      />
    </div>
    """
  end

  defp navigation_items(vault_unlocked) do
    project_vault_icon =
      if vault_unlocked, do: "lucide-lock-open", else: "lucide-lock"

    items = [
      %{id: :home, label: "Dashboard", icon: "lucide-house"},
      %{id: :projects, label: "Projects", icon: "lucide-folder"},
      %{id: :project_vault, label: "Project Vault", icon: project_vault_icon}
    ]

    if secrets_vault_enabled?() do
      items ++ [%{id: :secrets_vault, label: "Secrets Vault", icon: "lucide-key"}]
    else
      items
    end
  end

  defp secrets_vault_enabled? do
    Application.get_env(:suchconfig_desktop, :secrets_vault_enabled, true) == true
  end

  defp vault_page?(page) when page in [:secrets_vault, :project_vault, :projects], do: true
  defp vault_page?(_), do: false

  defp close_command_palette_assigns(socket) do
    assign(socket,
      command_palette_open: false,
      command_palette_cursor: 0
    )
  end

  defp handle_palette_key(socket, "Escape") do
    {:noreply, close_command_palette_assigns(socket)}
  end

  defp handle_palette_key(socket, "ArrowDown") do
    max = palette_item_count(socket) - 1
    next = min(socket.assigns.command_palette_cursor + 1, max(max, 0))
    {:noreply, assign(socket, command_palette_cursor: next)}
  end

  defp handle_palette_key(socket, "ArrowUp") do
    prev = max(socket.assigns.command_palette_cursor - 1, 0)
    {:noreply, assign(socket, command_palette_cursor: prev)}
  end

  defp handle_palette_key(socket, "Enter") do
    id =
      socket
      |> palette_flat_items()
      |> Enum.at(socket.assigns.command_palette_cursor)
      |> case do
        %{id: id} -> id
        _ -> nil
      end

    if id do
      socket =
        socket
        |> close_command_palette_assigns()
        |> run_palette_command(id)

      {:noreply, socket}
    else
      {:noreply, socket}
    end
  end

  defp handle_palette_key(socket, _), do: {:noreply, socket}

  defp palette_item_count(socket) do
    socket |> palette_flat_items() |> length()
  end

  defp palette_flat_items(_socket) do
    alias SuchConfigDesktopWeb.Sc.CommandPalette.Commands

    secrets_vault_enabled?()
    |> Commands.groups()
    |> Commands.flat_items()
  end

  defp parse_index(index) when is_binary(index) do
    case Integer.parse(index) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_index(index) when is_integer(index), do: index
  defp parse_index(_), do: 0

  defp copy_generator_feedback(socket) do
    value = socket.assigns.generator_value

    if value != "" do
      socket =
        socket
        |> assign(generator_copied: true)

      if connected?(socket) do
        Process.send_after(self(), :clear_generator_copied, 3000)
      end

      socket
    else
      socket
    end
  end

  defp run_palette_command(socket, "nav.dash") do
    assign(socket, current_page: :home)
  end

  defp run_palette_command(socket, "nav.docs") do
    assign(socket, current_page: :docs)
  end

  defp run_palette_command(socket, "nav.proj") do
    navigate_to_project_vault(socket)
  end

  defp run_palette_command(socket, "nav.projects") do
    socket
    |> assign(current_page: :projects)
    |> maybe_notify_page_visible(:projects)
  end

  defp run_palette_command(socket, "nav.settings") do
    socket
    |> assign(current_page: :settings)
    |> maybe_notify_page_visible(:settings)
  end

  defp run_palette_command(socket, "nav.sec") do
    if secrets_vault_enabled?() do
      socket
      |> assign(current_page: :secrets_vault)
      |> maybe_notify_page_visible(:secrets_vault)
    else
      socket
    end
  end

  defp run_palette_command(socket, "nav.gen") do
    if secrets_vault_enabled?() do
      if socket.assigns[:show_generator_drawer] do
        Generator.close(socket)
      else
        socket
        |> assign(current_page: :secrets_vault)
        |> maybe_notify_page_visible(:secrets_vault)
        |> Generator.open(:standalone)
      end
    else
      socket
    end
  end

  defp run_palette_command(socket, "lock") do
    if socket.assigns.vault_unlocked and socket.assigns[:vault_session_id] do
      SuchConfigDesktop.VaultSessionRegistry.delete(socket.assigns.vault_session_id)

      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "vault:#{socket.assigns.vault_session_id}",
        :vault_locked_no_overlay
      )

      assign(socket,
        vault_unlocked: false,
        navigation_items: navigation_items(false)
      )
    else
      push_event(socket, "run_native_global_passkey_auth", %{})
    end
  end

  defp run_palette_command(socket, "new.proj") do
    socket =
      case socket.assigns.current_page do
        page when page in [:projects, :project_vault] -> socket
        _ -> assign(socket, current_page: :projects)
      end

    {:noreply, socket} = FolderEvents.open_new_folder_modal(%{}, socket)
    socket
  end

  defp run_palette_command(socket, id)
       when id in ["new.login", "new.api", "new.ssh", "new.note"] do
    type = String.replace_prefix(id, "new.", "")

    if secrets_vault_enabled?() do
      socket =
        socket
        |> assign(current_page: :secrets_vault)
        |> maybe_notify_page_visible(:secrets_vault)

      if is_binary(socket.assigns.vault_session_id) do
        Phoenix.PubSub.broadcast(
          SuchConfigDesktop.PubSub,
          "secrets_vault:#{socket.assigns.vault_session_id}",
          {:open_new_entry, type}
        )
      end

      socket
    else
      socket
    end
  end

  defp run_palette_command(socket, "export") do
    socket = navigate_to_project_vault(socket)

    if connected?(socket) do
      send(self(), {:palette_project_vault, :open_archive_export})
    end

    socket
  end

  defp run_palette_command(socket, "import") do
    socket = navigate_to_project_vault(socket)

    if connected?(socket) do
      send(self(), {:palette_project_vault, :open_archive_import})
    end

    socket
  end

  defp run_palette_command(socket, _), do: socket

  defp broadcast_project_vault(socket, message) do
    if is_binary(socket.assigns.vault_session_id) do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "project_vault:#{socket.assigns.vault_session_id}",
        message
      )
    end

    :ok
  end

  defp maybe_notify_page_visible(socket, :projects) do
    ProjectsFormatting.refresh_project_entries(socket)
  end

  defp maybe_notify_page_visible(socket, :secrets_vault) do
    if secrets_vault_enabled?() and is_binary(socket.assigns.vault_session_id) do
      Phoenix.PubSub.broadcast(
        SuchConfigDesktop.PubSub,
        "secrets_vault:#{socket.assigns.vault_session_id}",
        :load_vault_wide_view_data
      )
    end

    socket
  end

  defp maybe_notify_page_visible(socket, :settings) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      "settings:storage",
      :refresh_storage_stats
    )

    socket
  end

  defp maybe_notify_page_visible(socket, _), do: socket

  defp navigate_to_project_vault(socket) do
    socket
    |> ensure_selected_project()
    |> assign(current_page: :project_vault)
  end

  defp ensure_selected_project(socket) do
    if socket.assigns.selected_project_id do
      socket
    else
      case ProjectVault.list_project_folders() do
        [%{id: id, name: name} | _] ->
          assign(socket, selected_project_id: id, selected_project_name: name)

        _ ->
          socket
      end
    end
  end

  defp project_vault_live_id(nil, visible), do: "project_vault-none-#{visible}"
  defp project_vault_live_id(folder_id, visible), do: "project_vault-#{folder_id}-#{visible}"
end
