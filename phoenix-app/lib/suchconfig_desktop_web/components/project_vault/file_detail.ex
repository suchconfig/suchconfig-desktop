defmodule SuchConfigDesktopWeb.Components.ProjectVault.FileDetail do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting,
    only: [tag_badge_class: 1, tag_badge_label: 1]

  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktopWeb.Components.ProjectVault.BrokerCredentialRow
  alias SuchConfigDesktopWeb.Components.ProjectVault.MergeAuditPanel
  alias SuchConfigDesktopWeb.Components.ProjectVault.NoteEditor
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  attr :folders, :list, default: []
  attr :notes, :list, default: []
  attr :vault_items, :list, default: []
  attr :vault_item_tags, :map, default: %{}
  attr :selected_folder_id, :any, default: nil
  attr :selected_note_id, :any, default: nil
  attr :selected_vault_item_id, :any, default: nil
  attr :editor_focus, :atom, default: :note
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :vault_activity_visible, :boolean, default: false
  attr :merge_audit_recent, :list, default: []
  attr :note_title, :string, default: ""
  attr :note_category, :string, default: "generic_note"
  attr :note_categories, :list, default: []
  attr :note_raw_content, :string, default: ""
  attr :display_mode, :atom, default: :input
  attr :note_unlocked, :boolean, default: false
  attr :security_mode, :string, default: "global_passkey"
  attr :global_passkey_unlocked, :boolean, default: false
  attr :copy_all_copied, :boolean, default: false
  attr :env_var_value_copied, :map, default: %{}
  attr :env_var_all_copied, :map, default: %{}
  attr :new_note_form_highlight?, :boolean, default: false
  attr :crdt_enabled?, :boolean, default: false
  attr :linked_sync_status, :atom, default: :not_linked
  attr :selected_folder_linked_auto_sync, :boolean, default: false
  attr :vault_item_change_count, :integer, default: 0
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []
  attr :broker_ui_enabled?, :boolean, default: false
  attr :broker_item_enabled, :boolean, default: false
  attr :broker_placeholder, :string, default: ""
  attr :broker_credential_kind, :string, default: "api_key"
  attr :broker_inject_as, :string, default: "header"
  attr :broker_env_enabled_keys, :list, default: []
  attr :broker_env_entries, :list, default: []

  def file_detail(assigns) do
    category = detail_category(assigns)
    is_archive = category == "archive"

    assigns =
      assigns
      |> assign(:category, category)
      |> assign(:is_archive, is_archive)
      |> assign(:has_selection, has_selection?(assigns))
      |> assign(:show_empty_state, show_empty_state?(assigns))
      |> assign(:detail_icon, Formatting.file_row_icon(category, category))
      |> assign(:detail_icon_color, Formatting.file_row_icon_color(category, category))
      |> assign(:extension, Formatting.file_extension(assigns.note_title, category, category))
      |> assign(:modified_label, modified_label(assigns))
      |> assign(:pill_tone, if(is_archive, do: "warn", else: "ok"))
      |> assign(
        :pill_label,
        Formatting.detail_pill_label(category, assigns.vault_item_ui_enabled?)
      )
      |> assign(:show_tag_picker, show_tag_picker?(assigns))
      |> assign(
        :env_broker_mode?,
        Formatting.env_display_mode?(assigns.note_category, assigns.item_tags)
      )
      |> assign(:subline_tags, subline_tags(assigns))
      |> assign(
        :linked_project_path,
        Formatting.selected_folder_linked_path(assigns.folders, assigns.selected_folder_id)
      )

    ~H"""
    <div
      id="project-vault-file-detail"
      class={["file-detail", @show_empty_state && "empty"]}
    >
      <div :if={@vault_activity_visible} class="file-detail-body">
        <div class="pv-actions">
          <button
            type="button"
            phx-click="hide_vault_activity"
            id="vault-activity-back-button"
            class="btn sm"
          >
            <.icon name="chev-l" size={13} /> Back to editor
          </button>
        </div>
        <MergeAuditPanel.merge_audit_panel events={@merge_audit_recent} />
      </div>

      <div
        :if={!@vault_activity_visible && !@has_selection && @selected_folder_id}
        class="file-detail-body"
      >
        <NoteEditor.note_actions_bar
          :if={@vault_item_ui_enabled?}
          selected_folder_id={@selected_folder_id}
          selected_note_id={@selected_note_id}
          selected_vault_item_id={@selected_vault_item_id}
          editor_focus={@editor_focus}
          vault_item_ui_enabled?={@vault_item_ui_enabled?}
          note_unlocked={@note_unlocked}
          note_category={@note_category}
          display_mode={@display_mode}
          note_raw_content={@note_raw_content}
          security_mode={@security_mode}
          global_passkey_unlocked={@global_passkey_unlocked}
          copy_all_copied={@copy_all_copied}
          linked_project_path={@linked_project_path}
          linked_sync_status={@linked_sync_status}
          selected_folder_linked_auto_sync={@selected_folder_linked_auto_sync}
          vault_item_change_count={@vault_item_change_count}
          item_tags={@item_tags}
        />
      </div>

      <div
        :if={
          !@vault_activity_visible &&
            (@show_empty_state ||
               (!@has_selection && @selected_folder_id && !@vault_item_ui_enabled?))
        }
        style="text-align: center; color: var(--ink-3); padding: 40px"
      >
        <.icon name="file" size={24} style="opacity: .4" />
        <div style="margin-top: 12px; font-size: 13px">Select a file to preview</div>
      </div>

      <div :if={!@vault_activity_visible && @has_selection}>
        <div class="file-detail-head">
          <div class="icon-lg" style={"color: #{@detail_icon_color}"}>
            <.icon name={@detail_icon} size={20} />
          </div>
          <div style="min-width: 0; flex: 1">
            <h2>
              {@note_title}<span :if={@note_title != ""} class="ext">.{@extension}</span>
              <span
                :if={@linked_project_path}
                class="linked-path"
                title={@linked_project_path}
              >
                {@linked_project_path}
              </span>
            </h2>
            <div class="subline">
              <.pill :if={@pill_label} tone={@pill_tone}>{@pill_label}</.pill>
              <span :if={@pill_label && @subline_tags != []}>·</span>
              <span
                :for={tag <- @subline_tags}
                class={tag_badge_class(tag)}
              >
                {tag_badge_label(tag)}
                <button
                  :if={@show_tag_picker && tag != VaultItemTags.system_linked_tag()}
                  type="button"
                  phx-click="remove_item_tag"
                  phx-value-tag={tag}
                  class="ml-1 inline-flex rounded hover:bg-black/5 dark:hover:bg-white/10"
                  aria-label={"Remove tag #{tag}"}
                >
                  <.icon name="x" size={10} />
                </button>
              </span>
            </div>
          </div>
          <div class="actions">
            <button type="button" class="btn sm icon-only" title="History" disabled>
              <.icon name="history" size={14} />
            </button>
            <NoteEditor.item_tag_picker
              :if={@show_tag_picker}
              item_tags={@item_tags}
              tag_suggestions={@tag_suggestions}
            />
            <button type="button" class="btn sm icon-only" title="Copy path" disabled>
              <.icon name="copy" size={14} />
            </button>
          </div>
        </div>

        <div class="file-detail-meta">
          <div class="meta-cell">
            <div class="k">Size</div>
            <div class="v mono">—</div>
          </div>
          <div class="meta-cell">
            <div class="k">Modified</div>
            <div class="v">{@modified_label}</div>
          </div>
          <div class="meta-cell">
            <div class="k">CRDT</div>
            <div class="v" style="color: var(--moss)">
              {if @crdt_enabled?, do: "synced", else: "local"}
            </div>
          </div>
          <div class="meta-cell">
            <div class="k">Devices</div>
            <div class="v">{if @crdt_enabled?, do: "3", else: "1"}</div>
          </div>
        </div>

        <div class="file-detail-body">
          <div :if={@is_archive} class="sealed-card">
            <.icon name="lock" size={20} style="color: var(--plum)" />
            <div>
              <div style="font-weight: 500; color: var(--ink)">This archive is sealed</div>
              <div class="muted" style="font-size: 13px; margin-top: 4px">
                Unseal with your master passphrase to inspect contents.
              </div>
            </div>
            <button type="button" class="btn sm primary" style="margin-left: auto" disabled>
              <.icon name="unlock" size={13} /> Unseal
            </button>
          </div>

          <div :if={!@is_archive} id="project-vault-note-editor">
            <NoteEditor.note_actions_bar
              selected_folder_id={@selected_folder_id}
              selected_note_id={@selected_note_id}
              selected_vault_item_id={@selected_vault_item_id}
              editor_focus={@editor_focus}
              vault_item_ui_enabled?={@vault_item_ui_enabled?}
              note_unlocked={@note_unlocked}
              note_category={@note_category}
              display_mode={@display_mode}
              note_raw_content={@note_raw_content}
              security_mode={@security_mode}
              global_passkey_unlocked={@global_passkey_unlocked}
              copy_all_copied={@copy_all_copied}
              linked_project_path={@linked_project_path}
              linked_sync_status={@linked_sync_status}
              selected_folder_linked_auto_sync={@selected_folder_linked_auto_sync}
              vault_item_change_count={@vault_item_change_count}
              item_tags={@item_tags}
            />
            <NoteEditor.note_form
              note_category={@note_category}
              note_categories={@note_categories}
              editor_focus={@editor_focus}
              note_title={@note_title}
              note_raw_content={@note_raw_content}
              display_mode={@display_mode}
              global_passkey_unlocked={@global_passkey_unlocked}
              env_var_value_copied={@env_var_value_copied}
              env_var_all_copied={@env_var_all_copied}
              new_note_form_highlight?={@new_note_form_highlight?}
              expand_vertically?={false}
              vault_item_ui_enabled?={@vault_item_ui_enabled?}
              selected_vault_item_id={@selected_vault_item_id}
              broker_ui_enabled?={@broker_ui_enabled?}
              broker_env_enabled_keys={@broker_env_enabled_keys}
              item_tags={@item_tags}
              tag_suggestions={@tag_suggestions}
              markdown_workspace?={
                @editor_focus == :vault_item &&
                  Formatting.project_details_vault_item?(@note_title, @note_category)
              }
              hide_note_category_select?={
                @vault_item_ui_enabled? or
                  (@editor_focus == :vault_item &&
                     Formatting.project_details_vault_item?(@note_title, @note_category))
              }
            />
            <BrokerCredentialRow.broker_credential_row
              :if={!@env_broker_mode?}
              broker_ui_enabled?={@broker_ui_enabled?}
              broker_item_enabled={@broker_item_enabled}
              broker_placeholder={@broker_placeholder}
              broker_credential_kind={@broker_credential_kind}
              broker_inject_as={@broker_inject_as}
              selected_vault_item_id={@selected_vault_item_id}
            />
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp has_selection?(assigns) do
    not is_nil(assigns.selected_note_id) or not is_nil(assigns.selected_vault_item_id) or
      assigns.new_note_form_highlight?
  end

  defp show_empty_state?(assigns) do
    !assigns.vault_activity_visible && !has_selection?(assigns) &&
      is_nil(assigns.selected_folder_id)
  end

  defp detail_category(assigns) do
    cond do
      assigns.editor_focus == :vault_item -> assigns.note_category
      assigns.selected_note_id -> assigns.note_category
      true -> assigns.note_category
    end
  end

  defp modified_label(assigns) do
    cond do
      assigns.selected_note_id ->
        assigns.notes
        |> Enum.find(&(&1.id == assigns.selected_note_id))
        |> case do
          nil -> "—"
          note -> Formatting.format_relative_time(note.updated_at)
        end

      assigns.selected_vault_item_id ->
        assigns.vault_items
        |> Enum.find(&(&1.id == assigns.selected_vault_item_id))
        |> case do
          nil -> "—"
          item -> Formatting.format_relative_time(item.updated_at)
        end

      true ->
        "—"
    end
  end

  defp show_tag_picker?(assigns) do
    assigns.vault_item_ui_enabled? &&
      assigns.editor_focus == :vault_item &&
      (assigns.selected_vault_item_id || assigns.new_note_form_highlight?)
  end

  defp subline_tags(assigns) do
    cond do
      assigns.editor_focus == :vault_item &&
          (assigns.selected_vault_item_id || assigns.new_note_form_highlight?) ->
        assigns.item_tags

      assigns.selected_vault_item_id ->
        Map.get(assigns.vault_item_tags, assigns.selected_vault_item_id, [])

      true ->
        []
    end
  end
end
