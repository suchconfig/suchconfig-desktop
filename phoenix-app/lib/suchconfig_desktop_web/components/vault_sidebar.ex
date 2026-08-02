defmodule SuchConfigDesktopWeb.Components.VaultSidebar do
  @moduledoc """
  Shared vault sidebar: project and secrets vault folder lists.
  """

  use SuchConfigDesktopWeb, :html

  import SuchConfigDesktopWeb.CoreComponents, only: [icon: 1]

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting,
    only: [
      note_type_badge_class: 1,
      note_type_badge_label: 1,
      project_details_vault_item?: 2,
      tag_badge_class: 1,
      tag_badge_label: 1
    ]

  import SuchConfigDesktopWeb.SecretsVaultLive.Formatting,
    only: [kind_label: 1, kind_badge_class: 1]

  attr :folders, :list, required: true
  attr :notes, :list, required: true
  attr :vault_items, :list, default: []
  attr :vault_item_tags, :map, default: %{}
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :vault_activity_visible, :boolean, default: false
  attr :selected_folder_id, :any, default: nil
  attr :selected_note_id, :any, default: nil
  attr :selected_vault_item_id, :any, default: nil
  attr :folder_sidebar_expanded, :boolean, default: true

  def project_folder_list(assigns) do
    {pd_vault, other_vault} = vault_items_partition(assigns.vault_items)

    assigns =
      assigns
      |> assign(:vault_items_project_details, pd_vault)
      |> assign(:vault_items_other, other_vault)

    ~H"""
    <div class="flex h-full min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-gray-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-800">
      <div class="mb-3 flex shrink-0 flex-wrap gap-2 justify-start">
        <button
          type="button"
          phx-click="open_new_folder_modal"
          id="new-project-button"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-2.5 py-1.5 text-xs font-medium text-gray-700 shadow-sm transition hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
        >
          <.icon name="lucide-folder-plus" class="h-4 w-4" />
          <span>New Project</span>
        </button>
        <button
          type="button"
          phx-click="toggle_vault_activity"
          id="vault-activity-button"
          class={[
            "inline-flex shrink-0 items-center gap-1.5 rounded-lg border px-2.5 py-1.5 text-xs font-medium shadow-sm transition",
            if(@vault_activity_visible,
              do:
                "border-indigo-500 bg-indigo-50 text-indigo-800 dark:border-indigo-500 dark:bg-indigo-950/40 dark:text-indigo-200",
              else:
                "border-gray-300 bg-white text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
            )
          ]}
        >
          <.icon name="lucide-clock" class="h-4 w-4" />
          <span>Vault Activity</span>
        </button>
      </div>
      <div class="min-h-0 flex-1 space-y-2 overflow-y-auto pr-0.5">
        <div :for={folder <- @folders} class="space-y-1">
          <div class="flex items-stretch gap-1">
            <div class={[
              "min-w-0 flex-1 flex items-stretch rounded text-sm border transition",
              if(@selected_folder_id == folder.id,
                do: "border-blue-400 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300",
                else: "border-gray-200 dark:border-slate-600 text-gray-700 dark:text-slate-300"
              )
            ]}>
              <button
                type="button"
                phx-click="folder_row_click"
                phx-value-id={folder.id}
                id={"folder-row-#{folder.id}"}
                aria-expanded={@selected_folder_id == folder.id && @folder_sidebar_expanded}
                class="min-w-0 flex-1 text-left pl-3 pr-1 py-2 flex items-center gap-2 rounded-l border-0 bg-transparent transition hover:bg-white/50 dark:hover:bg-slate-800/40"
              >
                <.icon
                  name={
                    if(@selected_folder_id == folder.id && @folder_sidebar_expanded,
                      do: "lucide-chevron-up",
                      else: "lucide-chevron-down"
                    )
                  }
                  class={
                    "h-4 w-4 shrink-0 " <>
                      if(@selected_folder_id == folder.id,
                        do: "text-blue-600 dark:text-blue-400",
                        else: "text-gray-500 dark:text-slate-400"
                      )
                  }
                />
                <span class="block min-w-0 flex-1 truncate">{folder.name}</span>
              </button>
              <button
                type="button"
                phx-click="open_edit_folder"
                phx-value-id={folder.id}
                id={"folder-edit-#{folder.id}"}
                class="shrink-0 rounded-r border-0 pl-1 pr-2.5 py-2 text-gray-500 hover:text-blue-600 dark:text-slate-400 dark:hover:text-blue-400"
                aria-label={"Edit folder #{folder.name}"}
              >
                <.icon name="lucide-pencil" class="h-4 w-4" />
              </button>
            </div>
            <button
              :if={@selected_folder_id == folder.id && @folder_sidebar_expanded}
              type="button"
              phx-click="new_note"
              phx-value-project_folder_id={folder.id}
              id={"folder-new-note-#{folder.id}"}
              class="shrink-0 rounded border border-gray-200 bg-white px-2.5 py-2 text-gray-500 shadow-sm transition hover:border-indigo-300 hover:bg-indigo-50 hover:text-indigo-600 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-400 dark:hover:border-indigo-600 dark:hover:bg-indigo-950/30 dark:hover:text-indigo-300"
              aria-label={"New note in #{folder.name}"}
            >
              <.icon name="lucide-file-plus" class="h-4 w-4" />
            </button>
          </div>
          <div
            :if={
              @selected_folder_id == folder.id && @folder_sidebar_expanded &&
                (@notes != [] || (@vault_item_ui_enabled? && @vault_items != []))
            }
            class="ml-3 pl-2 border-l border-gray-200 dark:border-slate-600 space-y-1"
          >
            <button
              :for={
                item <-
                  if(@vault_item_ui_enabled?, do: @vault_items_project_details, else: [])
              }
              type="button"
              phx-click="select_vault_item"
              phx-value-id={item.id}
              class={[
                "w-full text-left px-2 py-1.5 rounded text-xs border transition",
                if(@selected_vault_item_id == item.id,
                  do:
                    "border-blue-400 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300",
                  else:
                    "border-gray-200 dark:border-slate-600 text-gray-700 dark:text-slate-300 hover:bg-gray-50 dark:hover:bg-slate-700"
                )
              ]}
            >
              <span class="flex items-center justify-between gap-2">
                <span class="truncate">{item.title}</span>
                <span class="flex shrink-0 flex-wrap justify-end gap-1">
                  <span
                    :for={tag <- Map.get(@vault_item_tags, item.id, []) |> Enum.take(3)}
                    class={tag_badge_class(tag)}
                  >
                    {tag_badge_label(tag)}
                  </span>
                </span>
              </span>
            </button>
            <button
              :for={note <- if(@vault_item_ui_enabled?, do: [], else: @notes)}
              type="button"
              phx-click="select_note"
              phx-value-id={note.id}
              class={[
                "w-full text-left px-2 py-1.5 rounded text-xs border transition",
                if(@selected_note_id == note.id && is_nil(@selected_vault_item_id),
                  do:
                    "border-blue-400 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300",
                  else:
                    "border-gray-200 dark:border-slate-600 text-gray-700 dark:text-slate-300 hover:bg-gray-50 dark:hover:bg-slate-700"
                )
              ]}
            >
              <span class="flex items-center justify-between gap-2">
                <span class="truncate">{note.title}</span>
                <span class={note_type_badge_class(note.note_type)}>
                  {note_type_badge_label(note.note_type)}
                </span>
              </span>
            </button>
            <button
              :for={item <- if(@vault_item_ui_enabled?, do: @vault_items_other, else: [])}
              type="button"
              phx-click="select_vault_item"
              phx-value-id={item.id}
              class={[
                "w-full text-left px-2 py-1.5 rounded text-xs border transition",
                if(@selected_vault_item_id == item.id,
                  do:
                    "border-blue-400 bg-blue-50 dark:bg-blue-900/30 text-blue-700 dark:text-blue-300",
                  else:
                    "border-gray-200 dark:border-slate-600 text-gray-700 dark:text-slate-300 hover:bg-gray-50 dark:hover:bg-slate-700"
                )
              ]}
            >
              <span class="flex items-center justify-between gap-2">
                <span class="truncate">{item.title}</span>
                <span class="flex shrink-0 flex-wrap justify-end gap-1">
                  <span
                    :for={tag <- Map.get(@vault_item_tags, item.id, []) |> Enum.take(3)}
                    class={tag_badge_class(tag)}
                  >
                    {tag_badge_label(tag)}
                  </span>
                </span>
              </span>
            </button>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :folders, :list, required: true
  attr :items, :list, required: true
  attr :selected_folder_id, :any, default: nil
  attr :selected_item_id, :any, default: nil
  attr :search_query, :string, default: ""

  def secrets_folder_list(assigns) do
    ~H"""
    <div class="flex h-full min-h-0 flex-1 flex-col overflow-hidden rounded-lg border border-gray-200 bg-white p-4 dark:border-slate-700 dark:bg-slate-800">
      <div class="mb-3 flex shrink-0 flex-wrap gap-2">
        <button
          type="button"
          phx-click="new_item"
          phx-value-secrets_vault_folder_id={@selected_folder_id}
          id="new-secret-button"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-indigo-500 bg-indigo-600 px-2.5 py-1.5 text-xs font-medium text-white shadow-sm transition hover:bg-indigo-700"
        >
          <.icon name="lucide-plus" class="h-4 w-4" />
          <span>New entry</span>
        </button>
        <button
          type="button"
          phx-click="open_new_folder_modal"
          id="new-secrets-folder-button"
          class="inline-flex shrink-0 items-center gap-1.5 rounded-lg border border-gray-300 bg-white px-2.5 py-1.5 text-xs font-medium text-gray-700 shadow-sm transition hover:bg-gray-50 dark:border-slate-600 dark:bg-slate-900 dark:text-slate-200 dark:hover:bg-slate-800"
        >
          <.icon name="lucide-folder-plus" class="h-4 w-4" />
          <span>New folder</span>
        </button>
      </div>
      <.form for={%{}} phx-change="search_change" id="secrets-search-form" class="mb-3 shrink-0">
        <input
          type="search"
          name="search"
          value={@search_query}
          placeholder="Search titles, usernames, URLs…"
          id="secrets-search-input"
          class="w-full rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm text-gray-900 shadow-sm dark:border-slate-600 dark:bg-slate-900 dark:text-slate-100"
        />
      </.form>
      <div class="mb-3 min-h-0 shrink-0 space-y-1 overflow-y-auto max-h-32">
        <div :for={folder <- @folders} class="flex items-stretch gap-1">
          <button
            type="button"
            phx-click="select_folder"
            phx-value-id={folder.id}
            id={"secrets-folder-#{folder.id}"}
            class={[
              "min-w-0 flex-1 text-left rounded-lg border px-3 py-2 text-sm transition",
              if(@selected_folder_id == folder.id,
                do:
                  "border-indigo-500 bg-indigo-50 text-indigo-800 dark:bg-indigo-950/40 dark:text-indigo-200",
                else:
                  "border-gray-200 text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:text-slate-300 dark:hover:bg-slate-700"
              )
            ]}
          >
            <span class="truncate">{folder.name}</span>
          </button>
          <button
            type="button"
            phx-click="open_edit_folder"
            phx-value-id={folder.id}
            id={"secrets-folder-edit-#{folder.id}"}
            class="shrink-0 rounded-lg border border-gray-200 px-2 py-2 text-gray-500 hover:text-indigo-600 dark:border-slate-600 dark:hover:text-indigo-300"
            aria-label={"Edit #{folder.name}"}
          >
            <.icon name="lucide-pencil" class="h-4 w-4" />
          </button>
        </div>
      </div>
      <div id="secrets-entry-list" class="min-h-0 flex-1 space-y-1 overflow-y-auto">
        <p :if={@items == []} class="text-xs text-gray-500 dark:text-slate-400 px-1 py-4 text-center">
          No entries in this folder yet.
        </p>
        <button
          :for={item <- @items}
          type="button"
          phx-click="select_item"
          phx-value-id={item.id}
          id={"secrets-entry-#{item.id}"}
          class={[
            "w-full text-left rounded-lg border px-3 py-2 text-sm transition",
            if(@selected_item_id == item.id,
              do:
                "border-indigo-500 bg-indigo-50 text-indigo-800 dark:bg-indigo-950/40 dark:text-indigo-200",
              else:
                "border-gray-200 text-gray-700 hover:bg-gray-50 dark:border-slate-600 dark:text-slate-300 dark:hover:bg-slate-700"
            )
          ]}
        >
          <span class="flex items-center justify-between gap-2">
            <span class="truncate font-medium">{item.title}</span>
            <span class={kind_badge_class(item.kind)}>{kind_label(item.kind)}</span>
          </span>
        </button>
      </div>
    </div>
    """
  end

  defp vault_items_partition(items) when is_list(items) do
    {pd, rest} =
      Enum.split_with(items, fn item ->
        project_details_vault_item?(item.title, item.kind)
      end)

    {Enum.sort_by(pd, &{&1.title, &1.id}), Enum.sort_by(rest, &{&1.title, &1.id})}
  end
end
