defmodule SuchConfigDesktopWeb.ProjectVaultLive do
  @moduledoc """
  Project Vault LiveView orchestrator.

  Thin entrypoint that wires mount/render/handle_info to event handler
  modules under `ProjectVaultLive.*` and rendering to function components
  under `Components.ProjectVault.*`. Business logic lives in
  `SuchConfigDesktop.ProjectVault` (and, for archives,
  `SuchConfigDesktop.ProjectVault.Archive`).
  """

  use SuchConfigDesktopWeb, :live_view

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  alias Phoenix.PubSub

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.AutoDetect

  alias SuchConfigDesktopWeb.Components.ProjectVault.ArchivePanel
  alias SuchConfigDesktopWeb.Components.ProjectVault.FileDetail
  alias SuchConfigDesktopWeb.Components.ProjectVault.FileList
  alias SuchConfigDesktopWeb.Components.ProjectVault.LinkProjectModal
  alias SuchConfigDesktopWeb.Components.ProjectVault.LocalBrokerModal
  alias SuchConfigDesktopWeb.Components.ProjectVault.Modals
  alias SuchConfigDesktopWeb.Components.ProjectVault.NewNote
  alias SuchConfigDesktopWeb.Components.ProjectVault.SecurityReportCardModal
  alias SuchConfigDesktopWeb.Components.ProjectVault.SyncReviewModal

  alias SuchConfigDesktopWeb.ProjectVaultLive.ArchiveEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.BrokerEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.BrokerItemEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.LinkedSyncEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.FolderEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.NoteEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.Passkey
  alias SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey

  def mount(_params, session, socket) do
    embedded = session["embedded"] == true
    folders = ProjectVault.list_project_folders()
    selected_folder = selected_folder_from_session(session, folders)
    vault_session_id = session["vault_session_id"]

    vault_key =
      if vault_session_id,
        do: SuchConfigDesktop.VaultSessionRegistry.get(vault_session_id),
        else: nil

    key = if is_binary(vault_key) and String.trim(vault_key) != "", do: vault_key, else: ""
    unlocked = key != ""

    vault_item_ui_enabled? =
      ProjectVault.feature_enabled?() and ProjectVault.vault_item_crdt_persistence_enabled?()

    initial_vault_items =
      if vault_item_ui_enabled? && selected_folder && selected_folder.id,
        do: ProjectVault.list_vault_items_by_folder(selected_folder.id),
        else: []

    socket =
      socket
      |> assign(
        page_title: "Project Vault",
        embedded: embedded,
        folders: folders,
        selected_folder_id: selected_folder && selected_folder.id,
        notes: (selected_folder && ProjectVault.list_notes_by_folder(selected_folder.id)) || [],
        selected_note_id: nil,
        note_unlocked: false,
        note_category: "generic_note",
        security_mode: "global_passkey",
        global_passkey_unlocked: unlocked,
        vault_password: key,
        vault_session_id: vault_session_id,
        show_global_passkey_modal: false,
        global_passkey_input: "",
        global_passkey_purpose: nil,
        vault_key_id: VaultKey.vault_key_id(),
        native_passkey_supported: false,
        native_passkey_platform: "unknown",
        native_passkey_provider: "unknown",
        note_categories: note_categories(),
        vault_item_mode: :legacy_note,
        crdt_enabled?: ProjectVault.feature_enabled?(),
        crdt_doc_id: nil,
        vault_item_kind: "generic_note",
        merge_audit_recent: ProjectVault.recent_merge_audit(10),
        vault_activity_visible: session["vault_activity_visible"] == true,
        folder_name: "",
        folder_description: "",
        folder_tags: "",
        new_folder_link_path: nil,
        new_folder_link_stage: :idle,
        new_folder_link_error: nil,
        new_folder_run_sentinel: false,
        show_edit_folder_modal: false,
        editing_folder_id: nil,
        edit_folder_name: "",
        edit_folder_delete_confirm: false,
        show_new_folder_modal: false,
        folder_sidebar_expanded: true,
        note_title: "",
        note_raw_content: "",
        display_mode: :input,
        copy_all_copied: false,
        env_var_value_copied: %{},
        env_var_all_copied: %{},
        show_save_modal: false,
        note_save_password: "",
        pending_note_attrs: nil,
        show_unlock_modal: false,
        unlock_password: "",
        pending_unlock_note_id: nil,
        pending_unlock_note_title: "",
        decrypt_failed_wrong_key: false,
        show_delete_modal: false,
        delete_modal_target: :note,
        pending_delete_note_id: nil,
        pending_delete_note_title: "",
        vault_items: initial_vault_items,
        selected_vault_item_id: nil,
        editor_focus: :note,
        vault_item_ui_enabled?: vault_item_ui_enabled?,
        pending_unlock_action: nil,
        show_link_project_modal: false,
        link_project_stage: :idle,
        link_project_preview: nil,
        link_project_project_data: nil,
        link_project_scan_path: nil,
        link_project_project_name: nil,
        link_project_vault_candidates: [],
        link_project_vault_selected: %{},
        link_project_ai_tooling: nil,
        link_project_scaffold_selected: %{},
        link_project_existing_notes_strategy: nil,
        link_project_error: nil,
        link_project_run_sentinel: false,
        import_stage: :idle,
        import_preview: nil,
        import_routing: %{},
        archive_binary: nil,
        archive_password: "",
        conflict_strategy: "duplicate",
        archive_panel_mode: :hidden,
        archive_export_destination_path: nil,
        info: nil,
        error: nil,
        new_note_form_highlight: false,
        show_new_note_modal: false,
        new_note_tags: "",
        linked_sync_status: :not_linked,
        selected_folder_linked_auto_sync: false,
        local_broker_license_enabled?: ProjectVault.local_broker_enabled?(),
        security_sentinel_license_enabled?: ProjectVault.security_sentinel_license_enabled?(),
        broker_project_enabled: false,
        broker_scope_id: "",
        broker_allowed_domains: "",
        broker_services: [],
        broker_cli_snippet: "",
        broker_snippet_copied: false,
        broker_running: false,
        broker_socket_path: "",
        broker_runtime_scope_id: "",
        broker_proxy_enabled: false,
        broker_proxy_url: "",
        broker_proxy_ca_fingerprint: "",
        broker_proxy_ca_pinned: false,
        broker_starting: false,
        broker_stopping: false,
        broker_runtime_error: nil,
        broker_ui_enabled?: false,
        broker_item_enabled: false,
        broker_placeholder: "",
        broker_credential_kind: "api_key",
        broker_inject_as: "header",
        broker_env_enabled_keys: [],
        broker_env_entries: [],
        show_local_broker_modal: false,
        show_sync_review_modal: false,
        show_sentinel_report_modal: false,
        sentinel_scanning: false,
        sentinel_scan_phase: nil,
        sentinel_scan_percent: 0,
        sentinel_scan_message: nil,
        sentinel_report_card: nil,
        sentinel_risk_badge: nil,
        sentinel_error: nil,
        sentinel_pending_path: nil,
        sentinel_pending_folder_id: nil,
        sentinel_manifest_item_id: nil,
        sync_review_disk_body: nil,
        sync_review_vault_body: nil,
        sync_review_diff_lines: [],
        sync_review_item_id: nil,
        sync_review_relative_path: nil,
        vault_item_change_count: 0,
        item_tags: [],
        vault_item_tags: %{},
        tag_suggestions: SuchConfigDesktop.ProjectVault.VaultItemTags.suggested_tags()
      )
      |> allow_upload(
        :archive_file,
        accept: ~w(
            .suchvault
            .suchconfig
            .json
            .bin
            .txt
            application/octet-stream
            application/json
            text/plain
            application/vnd.suchconfig.vault+octet-stream
          ),
        max_entries: 1,
        max_file_size: 50_000_000,
        auto_upload: true
      )

    if vault_session_id do
      PubSub.subscribe(SuchConfigDesktop.PubSub, "vault:#{vault_session_id}")
    end

    PubSub.subscribe(SuchConfigDesktop.PubSub, ProjectVault.merge_audit_pubsub_topic())

    socket = BrokerEvents.assign_broker_state(socket)

    {:ok, socket}
  end

  def handle_event("set_vault_password", params, socket),
    do: Passkey.set_vault_password(params, socket)

  def handle_event("create_folder", params, socket) do
    case FolderEvents.create(params, assign(socket, vault_activity_visible: false)) do
      {:noreply, socket} -> {:noreply, BrokerEvents.assign_broker_state(socket)}
      other -> other
    end
  end

  def handle_event("open_new_folder_modal", params, socket),
    do: FolderEvents.open_new_folder_modal(params, socket)

  def handle_event("cancel_new_folder_modal", params, socket),
    do: FolderEvents.cancel_new_folder_modal(params, socket)

  def handle_event("new_folder_form_change", params, socket),
    do: FolderEvents.new_folder_form_change(params, socket)

  def handle_event("select_folder", params, socket) do
    case FolderEvents.select(params, socket) do
      {:noreply, socket} -> {:noreply, BrokerEvents.assign_broker_state(socket)}
      other -> other
    end
  end

  def handle_event("folder_row_click", params, socket) do
    case FolderEvents.folder_row_click(params, socket) do
      {:noreply, socket} -> {:noreply, BrokerEvents.assign_broker_state(socket)}
      other -> other
    end
  end

  def handle_event("open_edit_folder", params, socket), do: FolderEvents.open_edit(params, socket)

  def handle_event("cancel_edit_folder", params, socket),
    do: FolderEvents.cancel_edit(params, socket)

  def handle_event("edit_folder_input", params, socket),
    do: FolderEvents.edit_folder_input(params, socket)

  def handle_event("save_edit_folder", params, socket), do: FolderEvents.save_edit(params, socket)

  def handle_event("delete_folder", params, socket),
    do: FolderEvents.delete_editing(params, socket)

  def handle_event("request_delete_folder", params, socket),
    do: FolderEvents.request_delete_folder(params, socket)

  def handle_event("cancel_delete_folder_confirm", params, socket),
    do: FolderEvents.cancel_delete_folder_confirm(params, socket)

  def handle_event("new_note", params, socket),
    do: NoteEvents.new(params, assign(socket, vault_activity_visible: false))

  def handle_event("close_new_note_modal", params, socket),
    do: NoteEvents.close_new_note_modal(params, socket)

  def handle_event("set_new_note_category", params, socket),
    do: NoteEvents.set_new_note_category(params, socket)

  def handle_event("set_display_mode", params, socket),
    do: NoteEvents.set_display_mode(params, socket)

  def handle_event("set_note_category", params, socket),
    do: NoteEvents.set_category(params, socket)

  def handle_event("update_note_form", params, socket), do: NoteEvents.update_form(params, socket)

  def handle_event("select_note", params, socket),
    do: NoteEvents.select(params, assign(socket, vault_activity_visible: false))

  def handle_event("save_note", params, socket), do: NoteEvents.save(params, socket)

  def handle_event("cancel_save_modal", params, socket),
    do: NoteEvents.cancel_save_modal(params, socket)

  def handle_event("cancel_unlock_modal", params, socket),
    do: NoteEvents.cancel_unlock_modal(params, socket)

  def handle_event("unlock_note_with_global_passkey", params, socket),
    do: NoteEvents.unlock_note_with_global_passkey(params, socket)

  def handle_event("show_per_note_unlock_modal", params, socket),
    do: NoteEvents.show_per_note_unlock_modal(params, socket)

  def handle_event("confirm_unlock_note", params, socket),
    do: NoteEvents.confirm_unlock_note(params, socket)

  def handle_event("confirm_save_note", params, socket),
    do: NoteEvents.confirm_save_note(params, socket)

  def handle_event("show_delete_note_modal", params, socket),
    do: NoteEvents.show_delete_modal(params, socket)

  def handle_event("cancel_delete_modal", params, socket),
    do: NoteEvents.cancel_delete_modal(params, socket)

  def handle_event("confirm_delete_note", params, socket),
    do: NoteEvents.confirm_delete_note(params, socket)

  def handle_event("copy_to_clipboard", params, socket),
    do: NoteEvents.copy_to_clipboard(params, socket)

  def handle_event("copy_all_env_vars", params, socket),
    do: NoteEvents.copy_all_env_vars(params, socket)

  def handle_event("copy_env_var_value", params, socket),
    do: NoteEvents.copy_env_var_value(params, socket)

  def handle_event("copy_env_var_all", params, socket),
    do: NoteEvents.copy_env_var_all(params, socket)

  def handle_event("set_security_mode", params, socket),
    do: Passkey.set_security_mode(params, socket)

  def handle_event("native_global_passkey_available", params, socket),
    do: Passkey.native_available(params, socket)

  def handle_event("native_global_passkey_auth_failed", params, socket),
    do: Passkey.native_auth_failed(params, socket)

  def handle_event("native_global_passkey_authenticated", params, socket),
    do: Passkey.native_authenticated(params, socket)

  def handle_event("show_global_passkey_modal", params, socket),
    do: Passkey.show_modal(params, socket)

  def handle_event("request_unlock", params, socket), do: Passkey.request_unlock(params, socket)

  def handle_event("cancel_global_passkey_modal", params, socket),
    do: Passkey.cancel_modal(params, socket)

  def handle_event("confirm_global_passkey", params, socket), do: Passkey.confirm(params, socket)

  def handle_event("export_archive", params, socket), do: ArchiveEvents.export(params, socket)

  def handle_event("set_import_options", params, socket),
    do: ArchiveEvents.set_import_options(params, socket)

  def handle_event("prepare_import_archive", params, socket),
    do: ArchiveEvents.prepare_import(params, socket)

  def handle_event("open_archive_export", params, socket),
    do: ArchiveEvents.open_archive_export(params, socket)

  def handle_event("open_archive_import", params, socket),
    do: ArchiveEvents.open_archive_import(params, socket)

  def handle_event("close_archive_panel", params, socket),
    do: ArchiveEvents.close_archive_panel(params, socket)

  def handle_event("cancel_import_modal", params, socket),
    do: ArchiveEvents.cancel_import(params, socket)

  def handle_event("preview_archive", params, socket),
    do: ArchiveEvents.preview_archive(params, socket)

  def handle_event("set_import_routing", params, socket),
    do: ArchiveEvents.set_routing(params, socket)

  def handle_event("set_import_routing_name", params, socket),
    do: ArchiveEvents.set_routing_name(params, socket)

  def handle_event("confirm_import_archive", params, socket),
    do: ArchiveEvents.confirm_import(params, socket)

  def handle_event("folder_selected", %{"path" => path}, socket) do
    cond do
      socket.assigns[:show_link_project_modal] &&
          socket.assigns[:link_project_stage] == :select_path ->
        send(self(), {:link_project_scan_disk, path})

        {:noreply,
         assign(socket,
           link_project_stage: :scanning,
           link_project_scan_path: path,
           link_project_error: nil,
           error: nil
         )}

      socket.assigns[:show_new_folder_modal] ->
        FolderEvents.folder_selected_for_new_project(path, socket)

      true ->
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
      VaultItemEvents.folder_select_error(params, socket)
    end
  end

  def handle_event("new_vault_item", params, socket),
    do: VaultItemEvents.new_vault_item(params, assign(socket, vault_activity_visible: false))

  def handle_event("select_vault_item", params, socket),
    do: VaultItemEvents.select_vault_item(params, assign(socket, vault_activity_visible: false))

  def handle_event("show_delete_vault_item_modal", params, socket),
    do: VaultItemEvents.show_delete_vault_item_modal(params, socket)

  def handle_event("open_link_project_modal", params, socket),
    do: VaultItemEvents.open_link_project_modal(params, socket)

  def handle_event("cancel_link_project_modal", params, socket),
    do: VaultItemEvents.cancel_link_project_modal(params, socket)

  def handle_event("confirm_link_project", params, socket),
    do: VaultItemEvents.confirm_link_project(params, socket)

  def handle_event("link_project_vault_toggle", params, socket),
    do: VaultItemEvents.link_project_vault_toggle(params, socket)

  def handle_event("link_project_scaffold_toggle", params, socket),
    do: VaultItemEvents.link_project_scaffold_toggle(params, socket)

  def handle_event("link_project_existing_notes_change", params, socket),
    do: VaultItemEvents.link_project_existing_notes_change(params, socket)

  def handle_event("link_project_sentinel_change", params, socket),
    do: VaultItemEvents.link_project_sentinel_change(params, socket)

  def handle_event("sync_push_to_project", params, socket),
    do: LinkedSyncEvents.sync_push_to_project(params, socket)

  def handle_event("sync_refresh_from_disk", params, socket),
    do: LinkedSyncEvents.sync_refresh_from_disk(params, socket)

  def handle_event("sync_review_accept", params, socket),
    do: LinkedSyncEvents.sync_review_accept(params, socket)

  def handle_event("sync_review_reject", params, socket),
    do: LinkedSyncEvents.sync_review_reject(params, socket)

  def handle_event("toggle_folder_auto_sync", params, socket),
    do: LinkedSyncEvents.toggle_folder_auto_sync(params, socket)

  def handle_event("upgrade_legacy_note", params, socket),
    do: LinkedSyncEvents.upgrade_legacy_note(params, socket)

  def handle_event("add_item_tag", params, socket),
    do: SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents.add_item_tag(params, socket)

  def handle_event("add_item_tag_from_input", params, socket),
    do:
      SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents.add_item_tag_from_input(
        params,
        socket
      )

  def handle_event("add_item_tag_keydown", params, socket),
    do:
      SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents.add_item_tag_keydown(
        params,
        socket
      )

  def handle_event("remove_item_tag", params, socket),
    do: SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents.remove_item_tag(params, socket)

  def handle_event("linked_file_changed", params, socket),
    do: LinkedSyncEvents.handle_linked_file_changed(socket, params)

  def handle_event("archive_export_folder_selected", %{"path" => path}, socket)
      when is_binary(path) do
    {:noreply, assign(socket, archive_export_destination_path: path, error: nil)}
  end

  def handle_event("archive_export_folder_selected", _, socket), do: {:noreply, socket}

  def handle_event("clear_archive_export_destination", _params, socket) do
    {:noreply, assign(socket, archive_export_destination_path: nil)}
  end

  def handle_event("toggle_vault_activity", _params, socket) do
    {:noreply, assign(socket, vault_activity_visible: !socket.assigns.vault_activity_visible)}
  end

  def handle_event("hide_vault_activity", _params, socket) do
    {:noreply, assign(socket, vault_activity_visible: false)}
  end

  def handle_event("open_local_broker_modal", params, socket),
    do: BrokerEvents.open_local_broker_modal(params, socket)

  def handle_event("close_local_broker_modal", params, socket),
    do: BrokerEvents.close_local_broker_modal(params, socket)

  def handle_event("toggle_project_broker", params, socket),
    do: BrokerEvents.toggle_project_broker(params, socket)

  def handle_event("broker_form_change", params, socket),
    do: BrokerEvents.broker_form_change(params, socket)

  def handle_event("add_broker_service", params, socket),
    do: BrokerEvents.add_broker_service(params, socket)

  def handle_event("remove_broker_service", params, socket),
    do: BrokerEvents.remove_broker_service(params, socket)

  def handle_event("save_broker_scope", params, socket),
    do: BrokerEvents.save_broker_scope(params, socket)

  def handle_event("copy_broker_cli_snippet", params, socket),
    do: BrokerEvents.copy_broker_cli_snippet(params, socket)

  def handle_event("toggle_broker_proxy", params, socket),
    do: BrokerEvents.toggle_broker_proxy(params, socket)

  def handle_event("start_project_broker", params, socket),
    do: BrokerEvents.start_project_broker(params, socket)

  def handle_event("stop_project_broker", params, socket),
    do: BrokerEvents.stop_project_broker(params, socket)

  def handle_event("broker_start_result", params, socket),
    do: BrokerEvents.broker_start_result(params, socket)

  def handle_event("broker_stop_result", params, socket),
    do: BrokerEvents.broker_stop_result(params, socket)

  def handle_event("broker_status_result", params, socket),
    do: BrokerEvents.broker_status_result(params, socket)

  def handle_event("sentinel_scan_result", params, socket),
    do: SentinelEvents.scan_result(params, socket)

  def handle_event("sentinel_scan_progress", params, socket),
    do: SentinelEvents.progress(params, socket)

  def handle_event("close_sentinel_report_modal", _params, socket),
    do: {:noreply, SentinelEvents.close_report_modal(socket)}

  def handle_event("sentinel_rescan", _params, socket),
    do: {:noreply, SentinelEvents.start_rescan(socket)}

  def handle_event("sentinel_view_manifest", _params, socket),
    do: {:noreply, SentinelEvents.open_manifest_item(socket)}

  def handle_event("sentinel_open_report_from_manifest", _params, socket),
    do: {:noreply, SentinelEvents.open_report_from_manifest(socket)}

  def handle_event("toggle_item_broker", params, socket),
    do: BrokerItemEvents.toggle_item_broker(params, socket)

  def handle_event("save_broker_placeholder", params, socket),
    do: BrokerItemEvents.save_broker_placeholder(params, socket)

  def handle_event("toggle_env_broker_key", params, socket),
    do: BrokerItemEvents.toggle_env_broker_key(params, socket)

  def render(assigns) do
    ~H"""
    <%= if @embedded do %>
      <.project_vault_content {assigns} />
    <% else %>
      <Layouts.app flash={@flash} main_class="px-0">
        <.project_vault_content {assigns} />
      </Layouts.app>
    <% end %>
    """
  end

  attr :embedded, :boolean, default: false
  attr :global_passkey_unlocked, :boolean, default: false
  attr :folders, :list, default: []
  attr :notes, :list, default: []
  attr :vault_items, :list, default: []
  attr :vault_item_tags, :map, default: %{}
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :vault_activity_visible, :boolean, default: false
  attr :selected_folder_id, :any, default: nil
  attr :selected_note_id, :any, default: nil
  attr :selected_vault_item_id, :any, default: nil
  attr :folder_sidebar_expanded, :boolean, default: true
  attr :crdt_enabled?, :boolean, default: false
  attr :merge_audit_recent, :list, default: []
  attr :info, :any, default: nil
  attr :error, :any, default: nil
  attr :decrypt_failed_wrong_key, :boolean, default: false
  attr :pending_unlock_note_id, :any, default: nil
  attr :editor_focus, :atom, default: :note
  attr :note_title, :string, default: ""
  attr :note_category, :string, default: "generic_note"
  attr :note_categories, :list, default: []
  attr :note_raw_content, :string, default: ""
  attr :display_mode, :atom, default: :input
  attr :note_unlocked, :boolean, default: false
  attr :security_mode, :string, default: "global_passkey"
  attr :copy_all_copied, :boolean, default: false
  attr :env_var_value_copied, :map, default: %{}
  attr :env_var_all_copied, :map, default: %{}
  attr :new_note_form_highlight, :boolean, default: false
  attr :show_new_note_modal, :boolean, default: false
  attr :new_note_tags, :string, default: ""
  attr :archive_panel_mode, :atom, default: :hidden
  attr :archive_password, :string, default: ""
  attr :archive_export_destination_path, :any, default: nil
  attr :uploads, :any, default: nil
  attr :conflict_strategy, :string, default: "duplicate"
  attr :local_broker_license_enabled?, :boolean, default: false
  attr :security_sentinel_license_enabled?, :boolean, default: false
  attr :broker_project_enabled, :boolean, default: false
  attr :broker_scope_id, :string, default: ""
  attr :broker_allowed_domains, :string, default: ""
  attr :broker_cli_snippet, :string, default: ""
  attr :broker_snippet_copied, :boolean, default: false
  attr :broker_running, :boolean, default: false
  attr :broker_socket_path, :string, default: ""
  attr :broker_runtime_scope_id, :string, default: ""
  attr :broker_starting, :boolean, default: false
  attr :broker_stopping, :boolean, default: false
  attr :broker_runtime_error, :string, default: nil
  attr :broker_ui_enabled?, :boolean, default: false
  attr :broker_item_enabled, :boolean, default: false
  attr :broker_placeholder, :string, default: ""
  attr :broker_credential_kind, :string, default: "api_key"
  attr :broker_inject_as, :string, default: "header"
  attr :broker_env_enabled_keys, :list, default: []
  attr :broker_env_entries, :list, default: []
  attr :show_local_broker_modal, :boolean, default: false
  attr :linked_sync_status, :atom, default: :not_linked
  attr :selected_folder_linked_auto_sync, :boolean, default: false
  attr :vault_item_change_count, :integer, default: 0
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []
  attr :show_global_passkey_modal, :boolean, default: false
  attr :global_passkey_purpose, :any, default: nil
  attr :vault_key_id, :string, default: nil
  attr :native_passkey_supported, :boolean, default: false
  attr :native_passkey_platform, :string, default: "unknown"
  attr :show_save_modal, :boolean, default: false
  attr :note_save_password, :string, default: ""
  attr :show_unlock_modal, :boolean, default: false
  attr :pending_unlock_note_title, :string, default: ""
  attr :unlock_password, :string, default: ""
  attr :import_stage, :atom, default: :idle
  attr :import_preview, :any, default: nil
  attr :import_routing, :map, default: %{}
  attr :show_delete_modal, :boolean, default: false
  attr :delete_modal_target, :atom, default: :note
  attr :pending_delete_note_title, :string, default: ""
  attr :show_sync_review_modal, :boolean, default: false
  attr :sync_review_diff_lines, :list, default: []
  attr :sync_review_relative_path, :string, default: nil
  attr :show_link_project_modal, :boolean, default: false
  attr :link_project_stage, :atom, default: :idle
  attr :link_project_scan_path, :any, default: nil
  attr :link_project_project_name, :any, default: nil
  attr :link_project_preview, :any, default: nil
  attr :link_project_vault_candidates, :list, default: []
  attr :link_project_vault_selected, :map, default: %{}
  attr :link_project_ai_tooling, :any, default: nil
  attr :link_project_scaffold_selected, :map, default: %{}
  attr :link_project_existing_notes_strategy, :any, default: nil
  attr :link_project_error, :any, default: nil
  attr :link_project_run_sentinel, :boolean, default: false
  attr :show_edit_folder_modal, :boolean, default: false
  attr :edit_folder_name, :string, default: ""
  attr :edit_folder_delete_confirm, :boolean, default: false
  attr :show_new_folder_modal, :boolean, default: false
  attr :folder_name, :string, default: ""
  attr :folder_description, :string, default: ""
  attr :folder_tags, :string, default: ""
  attr :new_folder_link_path, :any, default: nil
  attr :new_folder_link_stage, :atom, default: :idle
  attr :new_folder_link_error, :any, default: nil
  attr :new_folder_run_sentinel, :boolean, default: false

  defp project_vault_content(assigns) do
    project_count = length(assigns.folders)
    note_count = Formatting.folder_item_count(assigns.notes, assigns.vault_items)
    edits_today = Formatting.edits_today_count(assigns.merge_audit_recent)

    assigns =
      assigns
      |> assign(:project_count, project_count)
      |> assign(:note_count, note_count)
      |> assign(:edits_today, edits_today)

    ~H"""
    <div
      id="project-vault-root"
      class={["project-vault-page", !@embedded && "frame-inner--full"]}
      phx-hook="VaultKeyStore"
    >
      <div
        id="project-vault-linked-sync"
        phx-hook="LinkedProjectSync"
        data-linked-folder-id={@selected_folder_id}
        data-linked-root-path={selected_folder_linked_path(@folders, @selected_folder_id)}
        class="hidden"
        aria-hidden="true"
      >
      </div>
      <div id="vault-download-export-hooks" phx-hook="Download" class="hidden" aria-hidden="true">
      </div>

      <div :if={!@global_passkey_unlocked} class="vault-unlock">
        <.sc_icon name="lock" size={32} />
        <h2 style="margin: 16px 0 8px; font-family: var(--font-serif); font-weight: 400">
          Unlock Global Passkey
        </h2>
        <p class="muted" style="max-width: 40ch; margin: 0 auto 20px">
          Project Vault and secure notes require an unlocked vault. Use Touch ID or your password to unlock.
        </p>
        <button type="button" phx-click="request_unlock" class="btn primary">
          Unlock Global Passkey
        </button>
      </div>

      <div :if={@global_passkey_unlocked}>
        <section class="pv-bar">
          <div class="pv-bar-stats">
            <span><b>{@project_count}</b> projects · <b>{@note_count}</b> notes</span>
            <span class="sep">·</span>
            <span><b>{@edits_today}</b> edits today</span>
            <span class="sep">·</span>
            <span>
              merge conflicts <span class="mono" style="color: var(--moss)">0 pending</span>
            </span>
          </div>
          <div class="pv-bar-actions">
            <button
              :if={
                @selected_folder_id &&
                  selected_folder_linked_path(@folders, @selected_folder_id)
              }
              type="button"
              phx-click="sentinel_rescan"
              id="open-sentinel-scan-button"
              class="btn sm"
              disabled={@sentinel_scanning}
              title="Run Security Sentinel on the linked project folder"
            >
              <.sc_icon name="shield" size={13} /> Sentinel Scan
            </button>
            <button
              :if={@selected_folder_id}
              type="button"
              phx-click="open_local_broker_modal"
              id="open-local-broker-button"
              class="btn sm"
              title="Local Broker settings for this project"
            >
              <.sc_icon name="key" size={13} /> Local Broker
            </button>
            <button
              type="button"
              phx-click="toggle_vault_activity"
              id="vault-activity-button"
              class={["btn sm", @vault_activity_visible && "primary"]}
            >
              <.sc_icon name="history" size={13} /> Activity
            </button>
            <button
              type="button"
              phx-click="open_archive_export"
              id="open-archive-export"
              class="btn sm"
            >
              <.sc_icon name="up" size={13} /> Export archive
            </button>
            <button
              type="button"
              phx-click="new_note"
              phx-value-project_folder_id={@selected_folder_id}
              class="btn sm primary"
              id="pv-new-note-button"
            >
              <.sc_icon name="plus" size={13} /> New note
            </button>
          </div>
        </section>

        <p :if={@info} class="vault-flash ok">{@info}</p>
        <p :if={@error} class="vault-flash err">{@error}</p>

        <div
          :if={@decrypt_failed_wrong_key && @pending_unlock_note_id}
          class="vault-flash err"
          style="margin-bottom: 12px"
        >
          <p>This note could not be decrypted with the current vault key.</p>
          <div class="row" style="margin-top: 10px">
            <button type="button" phx-click="show_per_note_unlock_modal" class="btn xs">
              Note password
            </button>
            <button type="button" phx-click="show_delete_note_modal" class="btn xs danger">
              Delete note
            </button>
          </div>
        </div>

        <div
          id="project-vault-split"
          class="pv-split"
          phx-hook="ResizableSplit"
          data-storage-key="sc:pvSplit"
          data-default-pct="33.33"
          data-min="22"
          data-max="70"
        >
          <FileList.file_list
            folders={@folders}
            selected_folder_id={@selected_folder_id}
            selected_note_id={@selected_note_id}
            selected_vault_item_id={@selected_vault_item_id}
            notes={@notes}
            vault_items={@vault_items}
            vault_item_ui_enabled?={@vault_item_ui_enabled?}
            crdt_enabled?={@crdt_enabled?}
            local_broker_license_enabled?={@local_broker_license_enabled?}
            broker_running={@broker_running}
            sentinel_risk_badge={@sentinel_risk_badge}
            note_title={@note_title}
            editor_focus={@editor_focus}
          />

          <div
            class="pv-resizer"
            role="separator"
            aria-orientation="vertical"
            aria-label="Resize file list / detail"
            tabindex="0"
            data-resizer
            title="Drag to resize · double-click to reset"
          >
            <span class="pv-resizer-grip" />
          </div>

          <FileDetail.file_detail
            folders={@folders}
            notes={@notes}
            vault_items={@vault_items}
            vault_item_tags={@vault_item_tags}
            selected_folder_id={@selected_folder_id}
            selected_note_id={@selected_note_id}
            selected_vault_item_id={@selected_vault_item_id}
            editor_focus={@editor_focus}
            vault_item_ui_enabled?={@vault_item_ui_enabled?}
            vault_activity_visible={@vault_activity_visible}
            merge_audit_recent={@merge_audit_recent}
            note_title={@note_title}
            note_category={@note_category}
            note_categories={@note_categories}
            note_raw_content={@note_raw_content}
            display_mode={@display_mode}
            note_unlocked={@note_unlocked}
            security_mode={@security_mode}
            global_passkey_unlocked={@global_passkey_unlocked}
            copy_all_copied={@copy_all_copied}
            env_var_value_copied={@env_var_value_copied}
            env_var_all_copied={@env_var_all_copied}
            new_note_form_highlight?={@new_note_form_highlight}
            crdt_enabled?={@crdt_enabled?}
            linked_sync_status={@linked_sync_status}
            selected_folder_linked_auto_sync={@selected_folder_linked_auto_sync}
            vault_item_change_count={@vault_item_change_count}
            item_tags={@item_tags}
            tag_suggestions={@tag_suggestions}
            broker_ui_enabled?={@broker_ui_enabled?}
            broker_item_enabled={@broker_item_enabled}
            broker_placeholder={@broker_placeholder}
            broker_credential_kind={@broker_credential_kind}
            broker_inject_as={@broker_inject_as}
            broker_env_enabled_keys={@broker_env_enabled_keys}
            broker_env_entries={@broker_env_entries}
          />
        </div>

        <ArchivePanel.archive_panel
          mode={@archive_panel_mode}
          archive_password={@archive_password}
          archive_export_destination_path={@archive_export_destination_path}
          uploads={@uploads}
          conflict_strategy={@conflict_strategy}
        />
        <LocalBrokerModal.local_broker_modal
          show={@show_local_broker_modal}
          local_broker_license_enabled?={@local_broker_license_enabled?}
          broker_project_enabled={@broker_project_enabled}
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
        <Modals.passkey_modal
          show={@show_global_passkey_modal}
          global_passkey_purpose={@global_passkey_purpose}
          vault_key_id={@vault_key_id}
          native_passkey_supported={@native_passkey_supported}
          native_passkey_platform={@native_passkey_platform}
        />
        <Modals.save_modal show={@show_save_modal} note_save_password={@note_save_password} />
        <Modals.unlock_modal
          show={@show_unlock_modal}
          pending_unlock_note_title={@pending_unlock_note_title}
          unlock_password={@unlock_password}
        />
        <Modals.import_password_modal stage={@import_stage} archive_password={@archive_password} />
        <Modals.import_preview_modal
          stage={@import_stage}
          preview={@import_preview}
          routing={@import_routing}
          folders={@folders}
          conflict_strategy={@conflict_strategy}
        />
        <Modals.delete_modal
          show={@show_delete_modal}
          delete_modal_target={@delete_modal_target}
          pending_delete_note_title={@pending_delete_note_title}
        />
        <SyncReviewModal.sync_review_modal
          show={@show_sync_review_modal}
          diff_lines={@sync_review_diff_lines}
          relative_path={@sync_review_relative_path}
        />
        <LinkProjectModal.link_project_modal
          show={@show_link_project_modal}
          stage={@link_project_stage}
          scan_path={@link_project_scan_path}
          project_name={@link_project_project_name}
          vault_candidates={@link_project_vault_candidates}
          vault_selected={@link_project_vault_selected}
          ai_tooling={@link_project_ai_tooling}
          scaffold_selected={@link_project_scaffold_selected}
          existing_notes_strategy={@link_project_existing_notes_strategy}
          folder_has_items={Formatting.folder_item_count(@notes, @vault_items) > 0}
          error={@link_project_error}
          run_sentinel_scan={@link_project_run_sentinel}
          pro_plan?={@security_sentinel_license_enabled?}
        />
        <SecurityReportCardModal.security_report_card_modal
          show={@show_sentinel_report_modal}
          card={@sentinel_report_card}
          scanning={@sentinel_scanning}
          scan_percent={@sentinel_scan_percent}
          scan_message={@sentinel_scan_message}
          error={@sentinel_error}
          license_enabled?={@security_sentinel_license_enabled?}
        />
        <Modals.edit_folder_modal
          show={@show_edit_folder_modal}
          edit_folder_name={@edit_folder_name}
          edit_folder_delete_confirm={@edit_folder_delete_confirm}
        />
        <Modals.new_folder_modal
          show={@show_new_folder_modal}
          folder_name={@folder_name}
          folder_description={@folder_description}
          folder_tags={@folder_tags}
          link_stage={@new_folder_link_stage}
          link_path={@new_folder_link_path}
          link_error={@new_folder_link_error}
          run_sentinel_scan={@new_folder_run_sentinel}
          pro_plan?={@security_sentinel_license_enabled?}
        />
        <NewNote.new_note_modal
          show={@show_new_note_modal}
          vault_item_ui_enabled?={@vault_item_ui_enabled?}
          note_category={@note_category}
          note_title={@note_title}
          note_raw_content={@note_raw_content}
          new_note_tags={@new_note_tags}
          selected_folder_id={@selected_folder_id}
        />
      </div>
    </div>
    """
  end

  defp sc_icon(assigns), do: SuchConfigDesktopWeb.Sc.Icon.icon(assigns)

  def handle_info(:broker_start_timeout, socket) do
    {:noreply, BrokerEvents.broker_start_timeout(socket)}
  end

  def handle_info(:vault_merge_audit_updated, socket) do
    {:noreply, assign(socket, merge_audit_recent: ProjectVault.recent_merge_audit(10))}
  end

  def handle_info(:vault_unlocked, socket), do: Passkey.apply_vault_unlocked(socket)
  def handle_info({:trusted_folder_sync, _vault}, socket), do: {:noreply, socket}
  def handle_info({:p2p_lan_sync, _vault}, socket), do: {:noreply, socket}
  def handle_info(:trusted_folder_sync_now, socket), do: {:noreply, socket}
  def handle_info(:trusted_folder_verify_integrity, socket), do: {:noreply, socket}
  def handle_info(:open_trusted_folder_setup, socket), do: {:noreply, socket}
  def handle_info(:request_unlock, socket), do: {:noreply, socket}
  def handle_info(:vault_locked, socket), do: Passkey.apply_vault_locked_state(socket)
  def handle_info(:vault_locked_no_overlay, socket), do: Passkey.apply_vault_locked_state(socket)
  def handle_info(:do_lock_global_passkey, socket), do: Passkey.apply_vault_locked_state(socket)

  def handle_info(:reset_copy_all_copied, socket) do
    {:noreply, assign(socket, copy_all_copied: false)}
  end

  def handle_info({:reset_env_var_copied, :value, line_number_key}, socket) do
    {:noreply,
     assign(socket,
       env_var_value_copied: Map.delete(socket.assigns.env_var_value_copied, line_number_key)
     )}
  end

  def handle_info({:reset_env_var_copied, :all, line_number_key}, socket) do
    {:noreply,
     assign(socket,
       env_var_all_copied: Map.delete(socket.assigns.env_var_all_copied, line_number_key)
     )}
  end

  def handle_info({:link_project_scan_disk, path}, socket) do
    if socket.assigns.vault_item_ui_enabled? do
      result =
        try do
          AutoDetect.scan_disk(path)
        rescue
          e -> {:error, Exception.message(e)}
        end

      {:noreply, VaultItemEvents.apply_link_project_scan(socket, result)}
    else
      {:noreply,
       assign(socket,
         link_project_stage: :select_path,
         link_project_scan_path: nil,
         link_project_error: "CRDT vault items are not available on this build.",
         info: nil
       )}
    end
  end

  def handle_async(:sentinel_save_manifest, result, socket),
    do: {:noreply, SentinelEvents.save_manifest_done(result, socket)}

  defp selected_folder_from_session(session, folders) do
    case session_folder_id(session["selected_folder_id"]) do
      id when is_integer(id) ->
        Enum.find(folders, &(&1.id == id)) || List.first(folders)

      _ ->
        List.first(folders)
    end
  end

  defp session_folder_id(id) when is_integer(id), do: id

  defp session_folder_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {parsed, ""} -> parsed
      _ -> nil
    end
  end

  defp session_folder_id(_), do: nil
end
