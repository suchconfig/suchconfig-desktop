defmodule SuchConfigDesktopWeb.Components.ProjectVault.NoteEditor do
  @moduledoc """
  HEEx function components for the Project Vault note editor: the action bar
  (mode toggles, copy, delete, lock) and the note form + env-var copy panel.
  """

  use Phoenix.Component

  import SuchConfigDesktopWeb.CoreComponents, only: [icon: 1]

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting,
    only: [
      note_content_placeholder: 1,
      parse_env_entries: 1,
      tag_badge_class: 1,
      tag_badge_label: 1
    ]

  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  alias SuchConfigDesktop.ProjectVault.BrokerFrontmatter
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktopWeb.Sc.Icon, as: ScIcon

  attr :selected_folder_id, :any, default: nil
  attr :selected_note_id, :any, default: nil
  attr :selected_vault_item_id, :any, default: nil
  attr :editor_focus, :atom, default: :note
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :note_unlocked, :boolean, default: false
  attr :note_category, :string, default: "generic_note"
  attr :display_mode, :atom, default: :input
  attr :note_raw_content, :string, default: ""
  attr :security_mode, :string, default: "global_passkey"
  attr :global_passkey_unlocked, :boolean, default: false
  attr :copy_all_copied, :boolean, default: false
  attr :linked_project_path, :string, default: nil
  attr :linked_sync_status, :atom, default: :not_linked
  attr :selected_folder_linked_auto_sync, :boolean, default: false
  attr :vault_item_change_count, :integer, default: 0
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []

  def note_actions_bar(assigns) do
    ~H"""
    <div class="pv-actions">
      <button
        :if={
          Formatting.env_display_mode?(@note_category, @item_tags) &&
            env_editor_active?(
              @editor_focus,
              @selected_note_id,
              @selected_vault_item_id,
              @note_unlocked
            )
        }
        type="button"
        phx-click="set_display_mode"
        phx-value-mode="input"
        class={["btn xs", @display_mode == :input && "primary"]}
      >
        Edit
      </button>
      <button
        :if={
          Formatting.env_display_mode?(@note_category, @item_tags) &&
            env_editor_active?(
              @editor_focus,
              @selected_note_id,
              @selected_vault_item_id,
              @note_unlocked
            )
        }
        type="button"
        phx-click="set_display_mode"
        phx-value-mode="copy"
        class={["btn xs", @display_mode == :copy && "primary"]}
      >
        Display
      </button>
      <button
        :if={
          env_editor_active?(
            @editor_focus,
            @selected_note_id,
            @selected_vault_item_id,
            @note_unlocked
          )
        }
        type="button"
        id="copy-all-env-vars"
        phx-hook="CopyButton"
        data-copy-event="copy_all_env_vars"
        data-copy-payload={Jason.encode!(%{})}
        data-copy-text={@note_raw_content}
        class="btn xs"
      >
        <.icon
          name={if @copy_all_copied, do: "lucide-check", else: "lucide-clipboard"}
          class="w-3 h-3 inline mr-1"
        />
        {if @copy_all_copied,
          do: "Copied",
          else:
            if(Formatting.env_display_mode?(@note_category, @item_tags),
              do: "Copy env",
              else: "Copy all"
            )}
      </button>
      <button
        :if={@editor_focus == :note && @selected_note_id && @note_unlocked}
        type="button"
        phx-click="show_delete_note_modal"
        class="btn xs danger"
      >
        Delete note
      </button>
      <button
        :if={@vault_item_ui_enabled? && @editor_focus == :vault_item && @selected_vault_item_id}
        type="button"
        phx-click="show_delete_vault_item_modal"
        class="btn xs danger"
      >
        Delete item
      </button>
      <button
        :if={@vault_item_ui_enabled? && @editor_focus == :note && @selected_note_id}
        type="button"
        phx-click="upgrade_legacy_note"
        class="btn xs"
      >
        Upgrade item
      </button>
      <span
        :if={@linked_sync_status != :not_linked}
        class={["pill", sync_status_pill_tone(@linked_sync_status)]}
      >
        <span class="dot" />
        {sync_status_label(@linked_sync_status)}
      </span>
      <button
        :if={
          @editor_focus == :vault_item && @selected_vault_item_id && @linked_project_path &&
            @linked_sync_status in [:vault_ahead, :conflict]
        }
        type="button"
        id="sync-push-button"
        phx-click="sync_push_to_project"
        class="btn xs"
      >
        Push sync
      </button>
      <button
        :if={
          @editor_focus == :vault_item && @selected_vault_item_id && @linked_project_path &&
            @linked_sync_status in [:disk_ahead, :conflict, :in_sync]
        }
        type="button"
        id="sync-refresh-button"
        phx-click="sync_refresh_from_disk"
        class="btn xs"
      >
        Pull sync
      </button>
      <button
        :if={@linked_project_path && @selected_folder_id}
        type="button"
        phx-click="toggle_folder_auto_sync"
        class={["btn xs", @selected_folder_linked_auto_sync && "primary"]}
      >
        {if @selected_folder_linked_auto_sync, do: "Auto-sync on", else: "Auto-sync off"}
      </button>
      <span
        :if={@editor_focus == :vault_item && @vault_item_change_count > 0}
        class="faint"
        style="font-size: 11px; font-family: var(--font-mono)"
        title="Loro CRDT history entries for this item"
      >
        history · {@vault_item_change_count}
      </span>
    </div>
    """
  end

  attr :note_category, :string, default: "generic_note"
  attr :note_categories, :list, required: true
  attr :editor_focus, :atom, default: :note
  attr :note_title, :string, default: ""
  attr :note_raw_content, :string, default: ""
  attr :display_mode, :atom, default: :input
  attr :global_passkey_unlocked, :boolean, default: false
  attr :env_var_value_copied, :map, default: %{}
  attr :env_var_all_copied, :map, default: %{}
  attr :new_note_form_highlight?, :boolean, default: false
  attr :hide_note_category_select?, :boolean, default: false
  attr :expand_vertically?, :boolean, default: false
  attr :markdown_workspace?, :boolean, default: false
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :selected_vault_item_id, :any, default: nil
  attr :broker_ui_enabled?, :boolean, default: false
  attr :broker_env_enabled_keys, :list, default: []

  def note_form(assigns) do
    ~H"""
    <form
      phx-submit="save_note"
      phx-change="update_note_form"
      phx-debounce="150"
      class={[
        "note-preview note-preview-form",
        @new_note_form_highlight? && "ring-2 ring-[var(--accent)]"
      ]}
    >
      <div class={["grid grid-cols-1 gap-3", @expand_vertically? && "shrink-0"]}>
        <input type="hidden" name="note_category" value={@note_category} />
        <div :if={!@vault_item_ui_enabled? && !@hide_note_category_select?} class="grid grid-cols-1">
          <select
            name="note_category"
            phx-change="set_note_category"
            class="col-start-1 row-start-1 w-full appearance-none rounded-md bg-white py-1.5 pl-3 pr-8 text-sm text-gray-900 outline outline-1 -outline-offset-1 outline-gray-300 focus-visible:outline focus-visible:outline-2 focus-visible:-outline-offset-2 focus-visible:outline-indigo-600 dark:bg-white/5 dark:text-white dark:outline-white/10 dark:focus-visible:outline-indigo-500"
          >
            <option
              :for={{label, value} <- @note_categories}
              value={value}
              selected={@note_category == value}
            >
              {label}
            </option>
          </select>
          <.icon
            name="lucide-chevron-down"
            class="pointer-events-none col-start-1 row-start-1 mr-2 size-5 self-center justify-self-end text-gray-500 dark:text-gray-400"
          />
        </div>
        <input
          :if={@markdown_workspace?}
          type="hidden"
          name="note_title"
          value={@note_title}
        />
        <input
          :if={!@markdown_workspace?}
          type="text"
          name="note_title"
          value={@note_title}
          placeholder="Note title (example: staging.env)"
          class="title-input"
        />
      </div>
      <%= if !Formatting.env_display_mode?(@note_category, @item_tags) || @display_mode == :input do %>
        <div class={
          if(@expand_vertically?, do: "flex min-h-0 flex-1 flex-col gap-3", else: "space-y-3")
        }>
          <div
            :if={@note_category == "security_manifest"}
            id="security-manifest-editor-hint"
            class="rounded-md border border-amber-200 bg-amber-50/80 px-3 py-2.5 text-xs text-amber-950 dark:border-amber-800/60 dark:bg-amber-950/30 dark:text-amber-100"
            role="note"
          >
            <p style="margin: 0 0 6px; font-weight: 600">What this is</p>
            <p style="margin: 0; line-height: 1.5; opacity: 0.92">
              Durable Security Sentinel record for this project — findings, risk score, and allow-list
              state stored as CRDT JSON. Use the Report Card for a readable summary; run Sentinel Scan
              to refresh. Prefer not to hand-edit this body.
            </p>
            <button
              type="button"
              class="btn xs"
              style="margin-top: 8px"
              phx-click="sentinel_open_report_from_manifest"
            >
              Open Report Card
            </button>
          </div>
          <%= if @markdown_workspace? do %>
            <div
              id="markdown-workspace"
              phx-hook="MarkdownWorkspace"
              data-default-mode="split"
              data-mode="split"
              class="flex min-h-0 flex-1 flex-col gap-2"
            >
              <div
                class="gen-mode-switch md-mode-switch"
                role="group"
                aria-label="Markdown view mode"
              >
                <button
                  type="button"
                  data-md-mode="edit"
                  class="btn sm gen-mode-btn"
                  aria-pressed="false"
                >
                  <ScIcon.icon name="pencil" size={13} /> Edit
                </button>
                <button
                  type="button"
                  data-md-mode="split"
                  class="btn sm gen-mode-btn active"
                  aria-pressed="true"
                >
                  <ScIcon.icon name="columns-2" size={13} /> Split
                </button>
                <button
                  type="button"
                  data-md-mode="preview"
                  class="btn sm gen-mode-btn"
                  aria-pressed="false"
                >
                  <ScIcon.icon name="eye" size={13} /> Preview
                </button>
              </div>
              <div data-md-panes class="min-h-0 flex-1">
                <div data-md-editor-wrap class="flex min-h-0 min-w-0 flex-1 flex-col">
                  <textarea
                    id="project-vault-note-raw"
                    name="note_raw_content"
                    rows={if(@expand_vertically?, do: 10, else: 12)}
                    class={[
                      "w-full min-h-0 flex-1 basis-0 resize-y px-3 py-2 text-sm font-mono text-gray-900 dark:text-slate-100",
                      "rounded border border-gray-300 bg-white dark:border-slate-600 dark:bg-slate-900"
                    ]}
                    placeholder={note_content_placeholder(@note_category)}
                  >{@note_raw_content}</textarea>
                </div>
                <div
                  data-md-preview-wrap
                  class="flex min-h-0 min-w-0 flex-1 flex-col rounded border border-gray-300 bg-slate-50 dark:border-slate-600 dark:bg-slate-950"
                >
                  <div
                    id="project-vault-md-preview"
                    data-md-preview
                    phx-update="ignore"
                    class="markdown-preview-content min-h-0 flex-1 overflow-auto p-3 text-sm"
                  >
                  </div>
                </div>
              </div>
            </div>
          <% else %>
            <textarea
              name="note_raw_content"
              rows={if(@expand_vertically?, do: 10, else: 12)}
              class={if(@expand_vertically?, do: "min-h-[280px]", else: nil)}
              placeholder={note_content_placeholder(@note_category)}
            >{@note_raw_content}</textarea>
          <% end %>
          <div class="row" style="flex-wrap: wrap">
            <button type="submit" class="btn sm primary">
              Save
            </button>
            <button
              :if={!@global_passkey_unlocked}
              type="button"
              phx-click="show_global_passkey_modal"
              phx-value-purpose="unlock"
              class="text-sm text-indigo-600 dark:text-indigo-400 hover:text-indigo-700 dark:hover:text-indigo-300 underline"
            >
              Unlock with Touch ID or password
            </button>
            <span :if={@editor_focus == :note} class="text-xs text-gray-600 dark:text-slate-400">
              Secure notes use Global Passkey (Touch ID).
            </span>
            <span
              :if={@editor_focus == :vault_item && @note_category == "security_manifest"}
              class="text-xs text-gray-600 dark:text-slate-400"
            >
              Updated by Sentinel Scan. Report Card is the usual reading surface; this JSON is the durable record.
            </span>
            <span
              :if={@editor_focus == :vault_item && @note_category != "security_manifest"}
              class="text-xs text-gray-600 dark:text-slate-400"
            >
              Stored only on this device. Vault items use a local CRDT snapshot.
            </span>
          </div>
        </div>
      <% else %>
        <%= if @expand_vertically? do %>
          <div class="flex min-h-0 flex-1 flex-col">
            <.env_var_copy_panel
              tall_mode?={true}
              note_raw_content={@note_raw_content}
              env_var_value_copied={@env_var_value_copied}
              env_var_all_copied={@env_var_all_copied}
              broker_ui_enabled?={@broker_ui_enabled?}
              broker_env_enabled_keys={@broker_env_enabled_keys}
              selected_vault_item_id={@selected_vault_item_id}
            />
          </div>
        <% else %>
          <.env_var_copy_panel
            tall_mode?={false}
            note_raw_content={@note_raw_content}
            env_var_value_copied={@env_var_value_copied}
            env_var_all_copied={@env_var_all_copied}
            broker_ui_enabled?={@broker_ui_enabled?}
            broker_env_enabled_keys={@broker_env_enabled_keys}
            selected_vault_item_id={@selected_vault_item_id}
          />
        <% end %>
      <% end %>
    </form>
    """
  end

  attr :tall_mode?, :boolean, default: false
  attr :note_raw_content, :string, default: ""
  attr :env_var_value_copied, :map, default: %{}
  attr :env_var_all_copied, :map, default: %{}
  attr :broker_ui_enabled?, :boolean, default: false
  attr :broker_env_enabled_keys, :list, default: []
  attr :selected_vault_item_id, :any, default: nil

  def env_var_copy_panel(assigns) do
    broker_toggles? =
      assigns.broker_ui_enabled? && not is_nil(assigns.selected_vault_item_id)

    entries =
      assigns.note_raw_content
      |> parse_env_entries()
      |> Enum.map(fn entry ->
        Map.put(entry, :placeholder, BrokerFrontmatter.placeholder_for_env_key(entry.key))
      end)

    assigns =
      assigns
      |> assign(:broker_toggles?, broker_toggles?)
      |> assign(:env_entries, entries)

    ~H"""
    <div
      id={if(@broker_toggles?, do: "env-broker-keys-panel", else: nil)}
      class={[
        "env-var-copy-panel border border-gray-200 dark:border-slate-700 rounded-lg bg-gray-50 dark:bg-slate-900/40 p-3 space-y-2",
        if(@tall_mode?,
          do: "min-h-0 w-full flex-1 overflow-y-auto",
          else: "max-h-[420px] overflow-y-auto"
        )
      ]}
    >
      <div
        :if={@broker_toggles?}
        class="env-broker-display-hint faint"
      >
        Check keys to enable for Local Broker
      </div>
      <div
        :for={entry <- @env_entries}
        id={if(@broker_toggles?, do: "env-broker-row-#{entry.key}", else: nil)}
        class="flex items-center justify-between gap-2 p-2 rounded border border-gray-200 dark:border-slate-700 bg-white dark:bg-slate-800"
      >
        <div class="min-w-0 flex items-start gap-2">
          <label
            :if={@broker_toggles?}
            class="env-broker-toggle shrink-0"
            title="Enable for Local Broker"
          >
            <input
              type="checkbox"
              checked={entry.key in @broker_env_enabled_keys}
              phx-click="toggle_env_broker_key"
              phx-value-key={entry.key}
              phx-value-enabled={to_string(!(entry.key in @broker_env_enabled_keys))}
              id={"env-broker-toggle-#{entry.key}"}
            />
            <span class="sr-only">Broker</span>
          </label>
          <div class="min-w-0">
            <p class="text-xs font-semibold text-gray-900 dark:text-slate-100 break-all">
              {entry.key}
            </p>
            <p class="text-xs text-gray-600 dark:text-slate-300 break-all">{entry.value}</p>
            <p :if={@broker_toggles? && entry.placeholder} class="text-xs faint mono break-all">
              {entry.placeholder}
            </p>
          </div>
        </div>
        <div class="shrink-0 flex items-center gap-2">
          <button
            type="button"
            id={"copy-env-var-value-#{entry.line_number}"}
            phx-hook="CopyButton"
            data-copy-event="copy_env_var_value"
            data-copy-payload={Jason.encode!(%{line_number: entry.line_number})}
            data-copy-text={entry.value}
            class="px-2 py-1 text-xs rounded border border-gray-300 dark:border-slate-600 text-gray-700 dark:text-slate-300 hover:bg-gray-100 dark:hover:bg-slate-700 transition"
          >
            <.icon
              name={
                if @env_var_value_copied[to_string(entry.line_number)],
                  do: "lucide-check",
                  else: "lucide-clipboard"
              }
              class="w-3 h-3 inline mr-1"
            />
            {if @env_var_value_copied[to_string(entry.line_number)],
              do: "Copied",
              else: "Copy Value"}
          </button>
          <button
            type="button"
            id={"copy-env-var-all-#{entry.line_number}"}
            phx-hook="CopyButton"
            data-copy-event="copy_env_var_all"
            data-copy-payload={Jason.encode!(%{line_number: entry.line_number})}
            data-copy-text={"#{entry.key}=#{entry.value}"}
            class="px-2 py-1 text-xs rounded border border-gray-300 dark:border-slate-600 text-gray-700 dark:text-slate-300 hover:bg-gray-100 dark:hover:bg-slate-700 transition"
          >
            <.icon
              name={
                if @env_var_all_copied[to_string(entry.line_number)],
                  do: "lucide-check",
                  else: "lucide-clipboard"
              }
              class="w-3 h-3 inline mr-1"
            />
            {if @env_var_all_copied[to_string(entry.line_number)],
              do: "Copied",
              else: "Copy All"}
          </button>
        </div>
      </div>
      <div :if={@env_entries == []} class="text-sm text-gray-500 dark:text-slate-400">
        No environment variables detected in current note.
      </div>
    </div>
    """
  end

  defp env_editor_active?(:vault_item, _note_id, vault_item_id, _note_unlocked)
       when not is_nil(vault_item_id),
       do: true

  defp env_editor_active?(:note, note_id, _vault_item_id, true) when not is_nil(note_id), do: true
  defp env_editor_active?(_, _, _, _), do: false

  attr :item_tags, :list, default: []

  def item_tag_bar(assigns) do
    ~H"""
    <div class="rounded-md border border-gray-200 bg-gray-50/80 p-2.5 dark:border-slate-600 dark:bg-slate-900/50">
      <div class="mb-2 flex flex-wrap items-center gap-1.5">
        <span
          :for={tag <- @item_tags}
          class={tag_badge_class(tag)}
        >
          {tag_badge_label(tag)}
          <button
            :if={tag != VaultItemTags.system_linked_tag()}
            type="button"
            phx-click="remove_item_tag"
            phx-value-tag={tag}
            class="ml-1 inline-flex rounded hover:bg-black/5 dark:hover:bg-white/10"
            aria-label={"Remove tag #{tag}"}
          >
            <.icon name="lucide-x" class="h-3 w-3" />
          </button>
        </span>
        <span :if={@item_tags == []} class="text-xs text-gray-500 dark:text-slate-400">
          No tags yet
        </span>
      </div>
    </div>
    """
  end

  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []
  attr :id, :string, default: "vault-item-tag-picker"
  attr :form_id, :string, default: nil
  attr :form_target_id, :string, default: nil
  attr :title, :string, default: "Add tag"

  def item_tag_picker(assigns) do
    form_id = assigns[:form_id] || "#{assigns.id}-form"
    detached? = is_binary(assigns[:form_target_id]) and assigns.form_target_id != ""

    assigns =
      assigns
      |> assign(:form_id, form_id)
      |> assign(:detached_form?, detached?)
      |> assign(
        :available_tag_suggestions,
        available_tag_suggestions(assigns.item_tags, assigns.tag_suggestions)
      )

    ~H"""
    <div id={@id} class="tag-picker" phx-hook="TagPicker">
      <button
        type="button"
        data-tag-picker-trigger
        class="btn sm icon-only"
        title={@title}
        aria-label={@title}
        aria-haspopup="menu"
        aria-expanded="false"
      >
        <ScIcon.icon name="tag" size={14} />
      </button>
      <div data-tag-picker-menu class="tag-picker-menu" role="menu">
        <div :if={@detached_form?} class="tag-picker-form">
          <input
            type="text"
            name="new_item_tag"
            form={@form_target_id}
            autocomplete="off"
            placeholder="Create new tag…"
            class="tag-picker-input"
          />
          <button type="submit" form={@form_target_id} class="btn xs primary">Add</button>
        </div>
        <form
          :if={!@detached_form?}
          id={@form_id}
          phx-submit="add_item_tag_from_input"
          class="tag-picker-form"
        >
          <input
            type="text"
            name="new_item_tag"
            autocomplete="off"
            placeholder="Create new tag…"
            class="tag-picker-input"
          />
          <button type="submit" class="btn xs primary">Add</button>
        </form>
        <p :if={@available_tag_suggestions == []} class="tag-picker-empty">
          Type a name above to create your first tag.
        </p>
        <ul :if={@available_tag_suggestions != []} class="tag-picker-list">
          <li :for={tag <- @available_tag_suggestions}>
            <button
              type="button"
              role="menuitem"
              phx-click="add_item_tag"
              phx-value-tag={tag}
              class="tag-picker-option"
            >
              <ScIcon.icon name="tag" size={12} />
              <span>{tag}</span>
            </button>
          </li>
        </ul>
      </div>
    </div>
    """
  end

  defp available_tag_suggestions(item_tags, tag_suggestions) do
    applied =
      item_tags
      |> List.wrap()
      |> Enum.map(&VaultItemTags.normalize_tag/1)
      |> MapSet.new()

    tag_suggestions
    |> List.wrap()
    |> Enum.map(&VaultItemTags.normalize_tag/1)
    |> Enum.uniq()
    |> Enum.reject(&(&1 == "" or MapSet.member?(applied, &1)))
  end

  defp sync_status_label(:in_sync), do: "In sync"
  defp sync_status_label(:vault_ahead), do: "Changed in vault"
  defp sync_status_label(:disk_ahead), do: "Changed on disk"
  defp sync_status_label(:conflict), do: "Conflict"
  defp sync_status_label(_), do: "Not linked"

  defp sync_status_pill_tone(:conflict), do: "warn"
  defp sync_status_pill_tone(_), do: "ok"
end
