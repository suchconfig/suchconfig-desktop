defmodule SuchConfigDesktopWeb.SecretsVaultLive do
  @moduledoc """
  Secrets Vault LiveView: credential CRUD backed by Loro CRDT + encrypted SQLite.
  """

  use SuchConfigDesktopWeb, :live_view

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktopWeb.Components.ProjectVault.Modals, as: ProjectModals
  alias SuchConfigDesktopWeb.Components.SecretsVault.EntryDetail
  alias SuchConfigDesktopWeb.Components.SecretsVault.FolderToolbar
  alias SuchConfigDesktopWeb.Components.SecretsVault.Modals
  alias SuchConfigDesktopWeb.Components.SecretsVault.NewEntry
  alias SuchConfigDesktopWeb.Components.SecretsVault.SecretsStats
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey

  alias SuchConfigDesktopWeb.SecretsVaultLive.{
    EntryEvents,
    FolderEvents,
    Formatting,
    Generator,
    ManagerImportEvents,
    Passkey,
    TagEvents,
    ViewData
  }

  @impl true
  def mount(_params, session, socket) do
    embedded = session["embedded"] == true

    if SecretsVault.secrets_vault_enabled?() do
      {:ok, unassociated} = SecretsVault.ensure_unassociated_folder()
      folders = SecretsVault.list_folders()
      selected_folder_id = unassociated.id
      items = SecretsVault.list_items(selected_folder_id)

      Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, Generator.topic())

      vault_session_id = session["vault_session_id"]

      if is_binary(vault_session_id) do
        Phoenix.PubSub.subscribe(SuchConfigDesktop.PubSub, "secrets_vault:#{vault_session_id}")
      end

      socket =
        socket
        |> Passkey.restore_session_key(session)
        |> Passkey.subscribe_vault_lock()
        |> assign(
          page_title: "Secrets Vault",
          embedded: embedded,
          folders: folders,
          selected_folder_id: selected_folder_id,
          items: items,
          selected_item_id: nil,
          vault_panel: :stats,
          search_query: "",
          filter_types: [],
          filter_tags: [],
          filter_open: false,
          filter_panel_query: "",
          item_title: "",
          item_inserted_at: nil,
          item_updated_at: nil,
          entry_activity: [],
          item_last_used_at: nil,
          item_kind: "password",
          username: "",
          url: "",
          public_key: "",
          fingerprint: "",
          secret_body: "",
          show_secret: false,
          crdt_enabled?: SecretsVault.feature_enabled?(),
          secrets_vault_enabled?: true,
          show_global_passkey_modal: false,
          global_passkey_input: "",
          global_passkey_purpose: nil,
          vault_key_id: VaultKey.vault_key_id(),
          native_passkey_supported: false,
          native_passkey_platform: "unknown",
          native_passkey_provider: "unknown",
          pending_unlock_action: nil,
          show_new_folder_modal: false,
          folder_name: "",
          folder_description: "",
          show_edit_folder_modal: false,
          show_delete_folder_modal: false,
          editing_folder_id: nil,
          edit_folder_name: "",
          edit_folder_description: "",
          delete_folder_name: "",
          delete_folder_items_action: :move_to_deleted_items,
          delete_folder_busy: false,
          show_delete_modal: false,
          show_new_entry_modal: false,
          new_entry_tags: "",
          new_entry_folder_id: nil,
          entry_folder_id: nil,
          item_tags: [],
          generator_strength: nil,
          info: nil,
          error: nil,
          manager_import_open: false,
          manager_import_stage: :idle,
          manager_import_preview: nil,
          manager_import_result: nil,
          manager_import_duplicate_strategy: :keep_as_new
        )
        |> allow_upload(:manager_import_file,
          accept: ~w(.json application/json text/plain application/octet-stream),
          max_entries: 1,
          max_file_size: 50_000_000,
          auto_upload: true
        )
        |> then(fn socket ->
          if embedded, do: socket, else: assign(socket, Generator.default_assigns())
        end)
        |> ViewData.assign_view_data()

      {:ok, socket}
    else
      {:ok,
       assign(socket,
         page_title: "Secrets Vault",
         embedded: embedded,
         secrets_vault_enabled?: false
       )}
    end
  end

  @impl true
  def handle_event("request_unlock", params, socket), do: Passkey.request_unlock(params, socket)

  def handle_event("cancel_global_passkey_modal", params, socket),
    do: Passkey.cancel_modal(params, socket)

  def handle_event("confirm_global_passkey", params, socket), do: Passkey.confirm(params, socket)

  def handle_event("native_passkey_available", params, socket),
    do: Passkey.native_available(params, socket)

  def handle_event("native_global_passkey_auth_failed", params, socket),
    do: Passkey.native_auth_failed(params, socket)

  def handle_event("native_global_passkey_authenticated", params, socket),
    do: Passkey.native_authenticated(params, socket)

  def handle_event("lock_global_passkey", params, socket), do: Passkey.lock(params, socket)

  def handle_event("vault_key_stored", _params, socket), do: {:noreply, socket}

  def handle_event("select_folder", params, socket),
    do: FolderEvents.select_folder(params, socket)

  def handle_event("folder_toolbar_change", params, socket),
    do: FolderEvents.folder_toolbar_change(params, socket)

  def handle_event("open_new_folder_modal", params, socket),
    do: FolderEvents.open_new_folder_modal(params, socket)

  def handle_event("close_new_folder_modal", params, socket),
    do: FolderEvents.close_new_folder_modal(params, socket)

  def handle_event("create_folder", params, socket),
    do: FolderEvents.create_folder(params, socket)

  def handle_event("open_edit_folder", params, socket),
    do: FolderEvents.open_edit_folder(params, socket)

  def handle_event("open_rename_folder", params, socket),
    do: FolderEvents.open_rename_folder(params, socket)

  def handle_event("close_edit_folder_modal", params, socket),
    do: FolderEvents.close_edit_folder_modal(params, socket)

  def handle_event("open_delete_folder_modal", params, socket),
    do: FolderEvents.open_delete_folder_modal(params, socket)

  def handle_event("close_delete_folder_modal", params, socket),
    do: FolderEvents.close_delete_folder_modal(params, socket)

  def handle_event("set_delete_folder_items_action", params, socket),
    do: FolderEvents.set_delete_folder_items_action(params, socket)

  def handle_event("delete_folder", params, socket),
    do: FolderEvents.delete_folder(params, socket)

  def handle_event("update_folder", params, socket),
    do: FolderEvents.update_folder(params, socket)

  def handle_event("toggle_filter_panel", params, socket),
    do: EntryEvents.toggle_filter_panel(params, socket)

  def handle_event("close_filter_panel", params, socket),
    do: EntryEvents.close_filter_panel(params, socket)

  def handle_event("filter_panel_search", params, socket),
    do: EntryEvents.filter_panel_search(params, socket)

  def handle_event("toggle_filter_type", params, socket),
    do: EntryEvents.toggle_filter_type(params, socket)

  def handle_event("toggle_filter_tag", params, socket),
    do: EntryEvents.toggle_filter_tag(params, socket)

  def handle_event("clear_filters", params, socket),
    do: EntryEvents.clear_filters(params, socket)

  def handle_event("search_change", params, socket), do: EntryEvents.search_change(params, socket)
  def handle_event("select_item", params, socket), do: EntryEvents.select_item(params, socket)

  def handle_event("show_vault_stats", params, socket),
    do: EntryEvents.show_vault_stats(params, socket)

  def handle_event("new_item", params, socket), do: EntryEvents.new_item(params, socket)

  def handle_event("close_new_entry_modal", params, socket),
    do: EntryEvents.close_new_entry_modal(params, socket)

  def handle_event("set_new_entry_kind", params, socket),
    do: EntryEvents.set_new_entry_kind(params, socket)

  def handle_event("entry_form_change", params, socket),
    do: EntryEvents.entry_form_change(params, socket)

  def handle_event("toggle_reveal", params, socket), do: EntryEvents.toggle_reveal(params, socket)
  def handle_event("copy_secret", params, socket), do: EntryEvents.copy_secret(params, socket)
  def handle_event("copy_username", params, socket), do: EntryEvents.copy_username(params, socket)

  def handle_event("copy_public_key", params, socket),
    do: EntryEvents.copy_public_key(params, socket)

  def handle_event("copy_fingerprint", params, socket),
    do: EntryEvents.copy_fingerprint(params, socket)

  def handle_event("save_item", params, socket), do: EntryEvents.save_item(params, socket)

  def handle_event("open_delete_modal", params, socket),
    do: EntryEvents.open_delete_modal(params, socket)

  def handle_event("close_delete_modal", params, socket),
    do: EntryEvents.close_delete_modal(params, socket)

  def handle_event("confirm_delete", params, socket),
    do: EntryEvents.confirm_delete(params, socket)

  def handle_event("open_generator_drawer", params, socket),
    do: EntryEvents.open_generator_drawer(params, socket)

  def handle_event("close_generator_drawer", params, socket),
    do: EntryEvents.close_generator_drawer(params, socket)

  def handle_event("roll_generator", params, socket),
    do: EntryEvents.roll_generator(params, socket)

  def handle_event("set_generator_mode", params, socket),
    do: EntryEvents.set_generator_mode(params, socket)

  def handle_event("set_generator_length", params, socket),
    do: EntryEvents.set_generator_length(params, socket)

  def handle_event("toggle_generator_opt", params, socket),
    do: EntryEvents.toggle_generator_opt(params, socket)

  def handle_event("copy_generator", params, socket),
    do: EntryEvents.copy_generator(params, socket)

  def handle_event("set_generator_password", params, socket),
    do: EntryEvents.set_generator_password(params, socket)

  def handle_event("set_generator_username", params, socket),
    do: EntryEvents.set_generator_username(params, socket)

  def handle_event("set_generator_username_form", params, socket),
    do: EntryEvents.set_generator_username_form(params, socket)

  def handle_event("add_item_tag", params, socket), do: TagEvents.add_item_tag(params, socket)

  def handle_event("add_item_tag_from_input", params, socket),
    do: TagEvents.add_item_tag_from_input(params, socket)

  def handle_event("remove_item_tag", params, socket),
    do: TagEvents.remove_item_tag(params, socket)

  def handle_event("open_manager_import", params, socket),
    do: ManagerImportEvents.open_wizard(params, socket)

  def handle_event("close_manager_import", params, socket),
    do: ManagerImportEvents.close_wizard(params, socket)

  def handle_event("manager_import_choose_source", params, socket),
    do: ManagerImportEvents.choose_source(params, socket)

  def handle_event("manager_import_back_source", params, socket),
    do: ManagerImportEvents.back_to_source(params, socket)

  def handle_event("manager_import_prepare_preview", params, socket),
    do: ManagerImportEvents.prepare_preview(params, socket)

  def handle_event("manager_import_set_duplicate_strategy", params, socket),
    do: ManagerImportEvents.set_duplicate_strategy(params, socket)

  def handle_event("manager_import_validate", params, socket),
    do: ManagerImportEvents.validate_upload(params, socket)

  def handle_event("manager_import_confirm", params, socket),
    do: ManagerImportEvents.confirm_import(params, socket)

  @impl true
  def handle_info({:generator_open, _context}, socket), do: {:noreply, socket}
  def handle_info(:generator_open, socket), do: {:noreply, socket}

  def handle_info(:clear_generator_copied, socket) do
    {:noreply, assign(socket, generator_copied: false)}
  end

  def handle_info({:generator_apply, value, strength}, socket) do
    {:noreply,
     assign(socket,
       secret_body: value,
       generator_strength: strength,
       info: "Password set on entry.",
       error: nil
     )}
  end

  def handle_info({:generator_apply_username, value}, socket) do
    {:noreply,
     assign(socket,
       username: value,
       info: "Username set on entry.",
       error: nil
     )}
  end

  def handle_info(:vault_locked, socket), do: Passkey.apply_vault_locked_state(socket)

  def handle_info(:vault_locked_no_overlay, socket), do: Passkey.apply_vault_locked_state(socket)

  def handle_info(:trusted_folder_sync_now, socket), do: {:noreply, socket}

  def handle_info(:trusted_folder_verify_integrity, socket), do: {:noreply, socket}

  def handle_info(:open_trusted_folder_setup, socket), do: {:noreply, socket}

  def handle_info(:request_unlock, socket), do: {:noreply, socket}

  def handle_info({:trusted_folder_sync, _vault}, socket), do: {:noreply, socket}
  def handle_info({:p2p_lan_sync, _vault}, socket), do: {:noreply, socket}

  @impl true
  def handle_info(:vault_unlocked, socket) do
    {:noreply, Passkey.apply_vault_unlocked(socket)}
  end

  def handle_info(:load_vault_wide_view_data, socket) do
    {:noreply, ViewData.assign_view_data(socket, load_all_items: true)}
  end

  def handle_info(:perform_delete_folder, socket) do
    FolderEvents.perform_delete_folder(socket)
  end

  def handle_info({:open_new_entry, type}, socket) when is_binary(type) do
    EntryEvents.new_item_of_type(type, socket)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%= if @embedded do %>
      <.secrets_vault_content {assigns} />
    <% else %>
      <Layouts.app flash={@flash} main_class="px-0">
        <.secrets_vault_content {assigns} />
      </Layouts.app>
    <% end %>
    """
  end

  attr :embedded, :boolean, default: false
  attr :secrets_vault_enabled?, :boolean, default: false
  attr :global_passkey_unlocked, :boolean, default: false
  attr :folders, :list, default: []
  attr :items, :list, default: []
  attr :selected_folder_id, :any, default: nil
  attr :selected_item_id, :any, default: nil
  attr :vault_panel, :atom, default: :stats
  attr :search_query, :string, default: ""
  attr :filter_types, :list, default: []
  attr :filter_tags, :list, default: []
  attr :filter_open, :boolean, default: false
  attr :filter_panel_query, :string, default: ""
  attr :item_title, :string, default: ""
  attr :item_inserted_at, :any, default: nil
  attr :item_updated_at, :any, default: nil
  attr :entry_activity, :list, default: []
  attr :item_last_used_at, :any, default: nil
  attr :item_kind, :string, default: "password"
  attr :username, :string, default: ""
  attr :url, :string, default: ""
  attr :public_key, :string, default: ""
  attr :fingerprint, :string, default: ""
  attr :secret_body, :string, default: ""
  attr :show_secret, :boolean, default: false
  attr :crdt_enabled?, :boolean, default: false
  attr :info, :any, default: nil
  attr :error, :any, default: nil
  attr :show_global_passkey_modal, :boolean, default: false
  attr :global_passkey_purpose, :any, default: nil
  attr :vault_key_id, :string, default: nil
  attr :native_passkey_supported, :boolean, default: false
  attr :native_passkey_platform, :string, default: "unknown"
  attr :native_passkey_provider, :string, default: "unknown"
  attr :show_new_folder_modal, :boolean, default: false
  attr :show_edit_folder_modal, :boolean, default: false
  attr :show_delete_folder_modal, :boolean, default: false
  attr :edit_folder_name, :string, default: ""
  attr :edit_folder_description, :string, default: ""
  attr :delete_folder_name, :string, default: ""
  attr :delete_folder_items_action, :atom, default: :move_to_deleted_items
  attr :delete_folder_busy, :boolean, default: false
  attr :show_delete_modal, :boolean, default: false
  attr :show_new_entry_modal, :boolean, default: false
  attr :new_entry_tags, :string, default: ""
  attr :new_entry_folder_id, :any, default: nil
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []
  attr :show_generator_drawer, :boolean, default: false
  attr :generator_value, :string, default: ""
  attr :generator_length, :integer, default: 20
  attr :generator_mode, :string, default: "password"
  attr :generator_opts, :map, default: %{}
  attr :generator_strength_level, :integer, default: 1
  attr :generator_strength_label, :string, default: "—"
  attr :generator_recent, :list, default: []
  attr :generator_context, :atom, default: :standalone
  attr :generator_copied, :boolean, default: false
  attr :manager_import_open, :boolean, default: false
  attr :manager_import_stage, :atom, default: :idle
  attr :manager_import_preview, :any, default: nil
  attr :manager_import_result, :any, default: nil
  attr :manager_import_duplicate_strategy, :atom, default: :keep_as_new
  attr :uploads, :any, default: nil

  defp secrets_vault_content(assigns) do
    ~H"""
    <div
      id="secrets-vault-root"
      class={["secrets-vault-page", !@embedded && "frame-inner--full"]}
      phx-hook="VaultKeyStore"
    >
      <div :if={!@secrets_vault_enabled?} class="vault-unlock">
        <p class="muted">Secrets Vault is disabled in configuration.</p>
      </div>

      <div :if={@secrets_vault_enabled?}>
        <section :if={@global_passkey_unlocked} class="pv-bar">
          <div class="pv-bar-stats">
            <span><b>{@entry_count}</b> entries</span>
            <span class="sep">·</span>
            <span><b>{@tag_count}</b> tags</span>
            <span class="sep">·</span>
            <span>
              last sync <span class="mono" style="color: var(--moss)">just now</span>
            </span>
          </div>
          <div class="pv-bar-actions">
            <button
              type="button"
              phx-click="show_vault_stats"
              class={["btn sm", @vault_panel == :stats && "primary"]}
              id="secrets-page-stats-button"
            >
              <.sc_icon name="stats" size={13} /> Stats
            </button>
            <button
              type="button"
              phx-click="new_item"
              phx-value-secrets_vault_folder_id={
                Formatting.new_entry_folder_param(@selected_folder_id)
              }
              class="btn sm primary"
              id="new-secret-button"
            >
              <.sc_icon name="plus" size={13} /> New entry
            </button>
            <button
              type="button"
              phx-click="open_manager_import"
              id="secrets-manager-import-button"
              class="btn sm"
            >
              <.sc_icon name="archive" size={13} /> Import
            </button>
            <button
              type="button"
              phx-click="lock_global_passkey"
              id="lock-secrets-vault-button"
              class="btn sm ghost"
            >
              Lock
            </button>
          </div>
        </section>

        <div :if={!@global_passkey_unlocked} class="vault-unlock">
          <.sc_icon name="lock" size={32} />
          <h2 style="margin: 16px 0 8px; font-family: var(--font-serif); font-weight: 400">
            Unlock Global Passkey
          </h2>
          <p class="muted" style="max-width: 40ch; margin: 0 auto 20px">
            Secrets Vault requires an unlocked vault. Use Touch ID or your password to unlock.
          </p>
          <button
            type="button"
            phx-click="request_unlock"
            id="secrets-vault-unlock-button"
            class="btn primary"
          >
            Unlock Global Passkey
          </button>
        </div>

        <div :if={@global_passkey_unlocked}>
          <p :if={@info} class="vault-flash ok">{@info}</p>
          <p :if={@error} class="vault-flash err">{@error}</p>
          <div
            id="secrets-vault-split"
            class="pv-split"
            phx-hook="ResizableSplit"
            phx-window-keydown="close_filter_panel"
            phx-key="Escape"
            data-storage-key="sc:svSplit"
            data-default-pct="33.33"
            data-min="22"
            data-max="70"
          >
            <div class="list-card">
              <FolderToolbar.folder_toolbar
                folders={@folders}
                selected_folder_id={@selected_folder_id}
              />
              <div
                class="list-toolbar"
                id="secrets-list-toolbar"
                phx-click-away="close_filter_panel"
              >
                <.form
                  for={%{}}
                  phx-change="search_change"
                  id="secrets-search-form"
                  class="list-toolbar-search"
                >
                  <input
                    type="search"
                    name="search"
                    value={@search_query}
                    placeholder="Search titles, tags, URLs…"
                    id="secrets-search-input"
                  />
                </.form>
                <.filter_button
                  id="secrets-filter"
                  open={@filter_open}
                  active_count={@filter_active_count}
                />
                <button type="button" class="btn xs icon-only" title="Sort" disabled>
                  <.sc_icon name="more" size={13} />
                </button>
                <.filter_panel {@filter_panel_assigns} open={@filter_open} />
              </div>
              <.filter_chips selected_types={@filter_types} selected_tags={@filter_tags} />
              <div id="secrets-entry-list" class="entry-list">
                <button
                  :for={item <- @filtered_items}
                  type="button"
                  phx-click="select_item"
                  phx-value-id={item.id}
                  id={"secrets-entry-#{item.id}"}
                  class={["entry", @selected_item_id == item.id && "active"]}
                >
                  <.type_glyph type={Formatting.glyph_type(item.kind)} />
                  <span style="min-width: 0">
                    <span class="entry-title">{item.title}</span>
                    <span class="entry-sub">{Formatting.entry_subtitle(item)}</span>
                  </span>
                  <span class="entry-meta">{Formatting.format_relative_time(item.updated_at)}</span>
                </button>
                <p :if={@filtered_items == []} class="vault-empty">
                  No matches. Try
                  <.kbd>⌘K</.kbd>
                </p>
              </div>
            </div>

            <div
              class="pv-resizer"
              role="separator"
              aria-orientation="vertical"
              aria-label="Resize entry list / detail"
              tabindex="0"
              data-resizer
              title="Drag to resize · double-click to reset"
            >
              <span class="pv-resizer-grip" />
            </div>

            <%= if @vault_panel == :detail && @selected_item_id do %>
              <EntryDetail.entry_detail
                global_passkey_unlocked={@global_passkey_unlocked}
                item_title={@item_title}
                item_kind={@item_kind}
                username={@username}
                url={@url}
                public_key={@public_key}
                fingerprint={@fingerprint}
                secret_body={@secret_body}
                show_secret={@show_secret}
                selected_item_id={@selected_item_id}
                folders={@folders}
                entry_folder_id={@entry_folder_id}
                item_inserted_at={@item_inserted_at}
                item_updated_at={@item_updated_at}
                entry_activity={@entry_activity}
                item_last_used_at={@item_last_used_at}
                generator_strength={@generator_strength}
                crdt_enabled?={@crdt_enabled?}
                generator_event_target={@generator_event_target}
                item_tags={@item_tags}
                tag_suggestions={@tag_suggestions}
              />
            <% else %>
              <SecretsStats.secrets_stats
                vault_stats={@vault_stats}
                folder_name={@folder_name}
              />
            <% end %>
          </div>
        </div>

        <ProjectModals.passkey_modal
          show={@show_global_passkey_modal}
          global_passkey_purpose={@global_passkey_purpose}
          vault_key_id={@vault_key_id}
          native_passkey_supported={@native_passkey_supported}
          native_passkey_platform={@native_passkey_platform}
        />
        <NewEntry.new_entry_modal
          show={@show_new_entry_modal}
          item_kind={@item_kind}
          item_title={@item_title}
          username={@username}
          url={@url}
          fingerprint={@fingerprint}
          secret_body={@secret_body}
          show_secret={@show_secret}
          folders={@folders}
          new_entry_folder_id={@new_entry_folder_id}
          new_entry_tags={@new_entry_tags}
          generator_event_target={@generator_event_target}
        />
        <Modals.new_folder_modal show={@show_new_folder_modal} />
        <Modals.edit_folder_modal
          show={@show_edit_folder_modal}
          edit_folder_name={@edit_folder_name}
          edit_folder_description={@edit_folder_description}
        />
        <Modals.delete_folder_modal
          show={@show_delete_folder_modal}
          delete_folder_name={@delete_folder_name}
          delete_folder_items_action={@delete_folder_items_action}
          delete_folder_busy={@delete_folder_busy}
        />
        <Modals.delete_modal show={@show_delete_modal} />
        <Modals.manager_import_modal
          show={@manager_import_open}
          stage={@manager_import_stage}
          preview={@manager_import_preview}
          result={@manager_import_result}
          duplicate_strategy={@manager_import_duplicate_strategy}
          error={@error}
          uploads={@uploads}
        />
        <.generator_drawer
          :if={!@embedded}
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
      </div>
    </div>
    """
  end

  defp sc_icon(assigns), do: SuchConfigDesktopWeb.Sc.Icon.icon(assigns)
end
