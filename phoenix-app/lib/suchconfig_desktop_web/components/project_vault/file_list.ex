defmodule SuchConfigDesktopWeb.Components.ProjectVault.FileList do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  attr :folders, :list, required: true
  attr :selected_folder_id, :any, default: nil
  attr :selected_note_id, :any, default: nil
  attr :selected_vault_item_id, :any, default: nil
  attr :notes, :list, default: []
  attr :vault_items, :list, default: []
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :crdt_enabled?, :boolean, default: false
  attr :local_broker_license_enabled?, :boolean, default: false
  attr :broker_running, :boolean, default: false
  attr :sentinel_risk_badge, :map, default: nil
  attr :note_title, :string, default: ""
  attr :editor_focus, :atom, default: :note

  def file_list(assigns) do
    folder_name =
      Enum.find_value(assigns.folders, "—", fn folder ->
        if folder.id == assigns.selected_folder_id, do: folder.name
      end)

    selected_title =
      cond do
        assigns.editor_focus == :vault_item && assigns.selected_vault_item_id ->
          assigns.note_title

        assigns.selected_note_id ->
          assigns.note_title

        true ->
          nil
      end

    badge = assigns.sentinel_risk_badge
    badge_grade = badge && (Map.get(badge, :overall_grade) || Map.get(badge, "overall_grade"))

    assigns =
      assigns
      |> assign(:folder_name, folder_name)
      |> assign(:selected_title, selected_title)
      |> assign(
        :linked_project_path,
        Formatting.selected_folder_linked_path(assigns.folders, assigns.selected_folder_id)
      )
      |> assign(:badge_grade, badge_grade)

    ~H"""
    <div class="pv-main @container">
      <div class="pv-toolbar">
        <div class="pv-toolbar-path">
          <.icon name="folder-open" size={15} style="color: var(--ink-2)" />
          <div class="path">
            {@folder_name}
            <span :if={@selected_title}> · <b>{@selected_title}</b></span>
          </div>
        </div>
        <div class="pv-toolbar-meta">
          <div class="pv-toolbar-pills">
            <.pill
              :if={@badge_grade}
              tone={sentinel_pill_tone(@badge_grade)}
              class="sentinel-risk-badge"
            >
              sentinel {@badge_grade}
            </.pill>
            <.pill :if={@crdt_enabled?} tone="ok">crdt synced</.pill>
            <.pill
              :if={@local_broker_license_enabled?}
              tone={if(@broker_running, do: "ok", else: "warn")}
            >
              {if @broker_running, do: "broker running", else: "broker stopped"}
            </.pill>
          </div>
          <div id="project-settings-picker" class="tag-picker" phx-hook="TagPicker">
            <button
              type="button"
              data-tag-picker-trigger
              id="project-settings-button"
              class="btn xs icon-only"
              title="Project settings"
              aria-label="Project settings"
              aria-haspopup="menu"
              aria-expanded="false"
            >
              <.icon name="settings-2" size={14} />
            </button>
            <div data-tag-picker-menu class="tag-picker-menu" role="menu">
              <ul class="tag-picker-list">
                <li :if={@selected_folder_id}>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click="open_edit_folder"
                    phx-value-id={@selected_folder_id}
                    id="open-project-settings"
                    class="tag-picker-option"
                    title="Edit project name and settings"
                  >
                    <.icon name="pencil" size={12} />
                    <span>Project settings</span>
                  </button>
                </li>
                <li :if={@vault_item_ui_enabled? && @selected_folder_id}>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click="open_link_project_modal"
                    id="link-project-button"
                    class="tag-picker-option"
                    title="Link a project folder on disk"
                  >
                    <.icon name="folder" size={12} />
                    <span>{link_project_button_label(@linked_project_path)}</span>
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click="open_archive_export"
                    id="note-open-archive-export"
                    class="tag-picker-option"
                  >
                    <.icon name="archive" size={12} />
                    <span>Export archive</span>
                  </button>
                </li>
                <li>
                  <button
                    type="button"
                    role="menuitem"
                    phx-click="open_archive_import"
                    id="open-archive-import"
                    class="tag-picker-option"
                  >
                    <.icon name="archive" size={12} />
                    <span>Import archive</span>
                  </button>
                </li>
              </ul>
            </div>
          </div>
        </div>
      </div>

      <div class="file-row file-head">
        <span />
        <span class="name min-w-0">Name</span>
        <span class="type shrink-0">Type</span>
        <span class="size @max-[26rem]:hidden">Size</span>
        <span class="when @max-[34rem]:hidden">Modified</span>
        <span />
      </div>

      <button
        :for={note <- if(@vault_item_ui_enabled?, do: [], else: @notes)}
        type="button"
        phx-click="select_note"
        phx-value-id={note.id}
        id={"project-file-note-#{note.id}"}
        class={[
          "file-row",
          @selected_note_id == note.id && is_nil(@selected_vault_item_id) && "active",
          @selected_note_id == note.id && is_nil(@selected_vault_item_id) && "selected"
        ]}
      >
        <span class="ico">
          <.icon
            name={Formatting.file_row_icon(note.note_type)}
            size={15}
            style={"color: #{Formatting.file_row_icon_color(note.note_type)}"}
          />
        </span>
        <span class="name min-w-0">
          <span class="min-w-0 truncate">{note.title}</span>
          <span class="ext shrink-0">.{Formatting.file_extension(note.title, note.note_type)}</span>
        </span>
        <span class="type shrink-0">
          <span class={Formatting.note_type_badge_class(note.note_type)}>
            {Formatting.note_type_badge_label(note.note_type)}
          </span>
        </span>
        <span class="size @max-[26rem]:hidden">—</span>
        <span class="when @max-[34rem]:hidden">
          {Formatting.format_relative_time(note.updated_at)}
        </span>
        <span class="ico"><.icon name="more" size={14} /></span>
      </button>

      <button
        :for={item <- if(@vault_item_ui_enabled?, do: @vault_items, else: [])}
        type="button"
        phx-click="select_vault_item"
        phx-value-id={item.id}
        id={"project-file-vault-#{item.id}"}
        class={[
          "file-row",
          @selected_vault_item_id == item.id && "active",
          @selected_vault_item_id == item.id && "selected"
        ]}
      >
        <span class="ico">
          <.icon
            name={Formatting.file_row_icon(item.kind)}
            size={15}
            style={"color: #{Formatting.file_row_icon_color(item.kind)}"}
          />
        </span>
        <span class="name min-w-0">
          <span class="min-w-0 truncate">{item.title}</span>
        </span>
        <span class="type shrink-0">
          <span class={Formatting.vault_item_badge_class(item.kind)}>
            {Formatting.vault_item_badge_label(item.kind)}
          </span>
        </span>
        <span class="size @max-[26rem]:hidden">—</span>
        <span class="when @max-[34rem]:hidden">
          {Formatting.format_relative_time(item.updated_at)}
        </span>
        <span class="ico" />
      </button>

      <p :if={@notes == [] && (@vault_items == [] || !@vault_item_ui_enabled?)} class="pv-empty">
        No notes in this project yet.
      </p>
    </div>
    """
  end

  defp link_project_button_label(path) when is_binary(path) do
    if String.trim(path) != "", do: "Update project link", else: "Link project"
  end

  defp link_project_button_label(_), do: "Link project"

  defp sentinel_pill_tone(grade) when grade in ["A", "B"], do: "ok"
  defp sentinel_pill_tone(_), do: "warn"
end
