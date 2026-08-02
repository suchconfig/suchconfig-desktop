defmodule SuchConfigDesktopWeb.Components.ProjectVault.ProjectsGrid do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  attr :project_entries, :list, required: true
  attr :expanded_projects, :map, default: %{}
  attr :vault_activity_visible, :boolean, default: false
  attr :total_item_count, :integer, default: 0

  def projects_grid(assigns) do
    project_count = length(assigns.project_entries)

    assigns =
      assigns
      |> assign(:project_count, project_count)

    ~H"""
    <div id="projects-page-root" class="projects-page w-full min-h-0 flex flex-col flex-1">
      <section class="pv-bar w-full">
        <div class="pv-bar-stats">
          <span><b>{@project_count}</b> projects · <b>{@total_item_count}</b> notes</span>
          <span class="sep">·</span>
          <span><b>{@project_count}</b> active</span>
          <span class="sep">·</span>
          <span>
            last sync <span class="mono" style="color: var(--moss)">just now</span>
          </span>
        </div>
        <div class="pv-bar-actions">
          <button
            type="button"
            phx-click="toggle_vault_activity"
            id="projects-activity-button"
            class={["btn sm", @vault_activity_visible && "primary"]}
          >
            <.icon name="history" size={13} /> Activity
          </button>
          <button
            type="button"
            phx-click="open_new_folder_modal"
            id="new-project-button"
            class="btn sm primary"
          >
            <.icon name="plus" size={13} /> New project
          </button>
        </div>
      </section>

      <div class="projects-page-body">
        <p :if={@project_count == 0} class="muted projects-empty">
          No projects yet. Create one to get started.
        </p>

        <div
          :if={@project_count > 0}
          class="grid w-full grid-cols-1 gap-[18px] items-start sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4"
        >
          <div
            :for={entry <- @project_entries}
            id={"project-card-#{entry.folder.id}"}
            class="ws-card min-w-0 cursor-pointer"
            phx-click="open_project"
            phx-value-id={entry.folder.id}
            role="button"
            tabindex="0"
            title={entry.folder.name}
          >
            <div class="ws-card-head">
              <div class="ws-card-glyph"><.icon name="vault" size={18} /></div>
              <div style="min-width: 0; flex: 1">
                <h3 class="truncate">{entry.folder.name}</h3>
                <div class="muted" style="font-size: 12px">
                  {entry.item_count} items
                  <span :if={entry.sealed_count > 0}> ·  {entry.sealed_count} sealed</span>
                </div>
              </div>
            </div>

            <div class="tree" style="background: transparent; border: 0; padding: 4px 0 0">
              <button
                type="button"
                phx-click="toggle_project_contents"
                phx-value-id={entry.folder.id}
                id={"project-contents-#{entry.folder.id}"}
                class="tree-node"
              >
                <span class="chev">
                  <.icon
                    name={
                      (Map.get(@expanded_projects, entry.folder.id, false) && "chev-d") || "chev-r"
                    }
                    size={12}
                  />
                </span>
                <span class="pico"><.icon name="folder-open" size={14} /></span>
                <span>Contents</span>
                <span class="count">{length(entry.children)}</span>
              </button>
              <div
                :for={child <- entry.children}
                :if={Map.get(@expanded_projects, entry.folder.id, false)}
                class="tree-node depth-1"
              >
                <span class="chev" />
                <span class="pico">
                  <.icon name={child_icon(child.kind)} size={14} />
                </span>
                <span>{child.name}</span>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp child_icon("archive"), do: "archive"
  defp child_icon(_), do: "file"
end
