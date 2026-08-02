defmodule SuchConfigDesktopWeb.Components.ProjectVault.LinkProjectModal do
  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  import SuchConfigDesktopWeb.ProjectVaultLive.Formatting,
    only: [note_type_badge_class: 1, note_type_badge_label: 1]

  attr :show, :boolean, default: false
  attr :stage, :atom, default: :idle
  attr :scan_path, :string, default: nil
  attr :project_name, :string, default: nil
  attr :vault_candidates, :list, default: []
  attr :vault_selected, :map, default: %{}
  attr :ai_tooling, :map, default: nil
  attr :scaffold_selected, :map, default: %{}
  attr :existing_notes_strategy, :string, default: nil
  attr :folder_has_items, :boolean, default: false
  attr :error, :string, default: nil
  attr :run_sentinel_scan, :boolean, default: false
  attr :pro_plan?, :boolean, default: false

  def link_project_modal(assigns) do
    ai = assigns.ai_tooling || %{}
    folder_tags = List.wrap(ai[:folder_tags] || ai["folder_tags"])
    found = List.wrap(ai[:found] || ai["found"])
    recommendations = List.wrap(ai[:recommendations] || ai["recommendations"])

    assigns =
      assign(assigns,
        ai_folder_tags: folder_tags,
        ai_found: found,
        ai_recommendations: recommendations,
        show_ai_panel: folder_tags != [] or found != [] or recommendations != []
      )

    ~H"""
    <.modal_shell
      show={@show}
      id="link-project-modal"
      on_cancel="cancel_link_project_modal"
      size="lg"
    >
      <.modal_head>
        <div style="display: flex; align-items: flex-start; justify-content: space-between; gap: 12px; width: 100%">
          <div style="flex: 1; min-width: 0">
            <h3 style="margin: 0">Link Project</h3>
            <p class="modal-hint" style="margin-top: 4px">
              Choose a folder on this device. We scan it locally to create Project Details and config notes in your vault.
            </p>
          </div>
          <button
            type="button"
            class="btn ghost sm icon-only close"
            phx-click="cancel_link_project_modal"
            aria-label="Close"
          >
            <.icon name="x" size={14} />
          </button>
        </div>
      </.modal_head>
      <.modal_body>
        <div :if={@error} class="vault-flash err" role="alert">
          {@error}
        </div>
        <div
          :if={@stage == :select_path || @stage == :scanning}
          id="vault-link-project-dropzone"
          phx-hook="DropZone"
          class="link-project-dropzone"
        >
          <%= if @stage == :scanning do %>
            <p style="margin: 0; font-weight: 500; color: var(--ink)">Scanning project…</p>
            <p :if={@scan_path} class="link-project-panel-path" style="margin-top: 8px">
              {@scan_path}
            </p>
          <% else %>
            <p style="margin: 0">Drop a project folder here or click to browse.</p>
          <% end %>
        </div>
        <div :if={@stage == :preview} class="modal-field">
          <div class="link-project-panel">
            <p class="link-project-panel-title">Linked folder</p>
            <p class="link-project-panel-path">{@scan_path}</p>
            <p :if={@project_name} class="modal-hint" style="margin-top: 6px">
              Project: <span class="strong">{@project_name}</span>
            </p>
          </div>
          <div :if={@show_ai_panel} class="link-project-panel" id="link-project-ai-tooling-panel">
            <p class="link-project-panel-title">AI tooling</p>
            <.modal_hint>
              Detected editor/agent ignore files. Selected missing files are created on Confirm and never overwrite existing files.
            </.modal_hint>
            <div
              :if={@ai_folder_tags != []}
              style="display: flex; flex-wrap: wrap; gap: 6px; margin-top: 8px"
            >
              <span
                :for={tag <- @ai_folder_tags}
                class="pill"
                style="font-size: 10px; padding: 2px 8px"
              >
                {tag}
              </span>
            </div>
            <div :if={@ai_found != []} style="margin-top: 10px">
              <p class="modal-hint" style="margin: 0 0 4px">Found</p>
              <ul class="link-candidates" style="margin: 0">
                <li :for={path <- @ai_found}>
                  <span class="link-candidate-path">{path}</span>
                </li>
              </ul>
            </div>
            <div :if={@ai_recommendations != []} style="margin-top: 10px">
              <p class="modal-hint" style="margin: 0 0 4px">Recommended create</p>
              <ul class="link-candidates">
                <li :for={{rec, idx} <- Enum.with_index(@ai_recommendations)}>
                  <button
                    type="button"
                    phx-click="link_project_scaffold_toggle"
                    phx-value-path={rec.path}
                    id={"link-project-scaffold-#{idx}"}
                    class={[
                      "link-candidate",
                      Map.get(@scaffold_selected, rec.path, false) && "is-selected"
                    ]}
                  >
                    <span class="link-candidate-path">{rec.path}</span>
                    <span class="link-candidate-meta">
                      <span class="pill" style="font-size: 10px; padding: 2px 6px">{rec.tool}</span>
                      <.icon
                        name={
                          if(Map.get(@scaffold_selected, rec.path, false),
                            do: "check",
                            else: "minus"
                          )
                        }
                        size={14}
                      />
                    </span>
                  </button>
                  <p class="modal-hint" style="margin: 2px 0 8px 4px">{rec.reason}</p>
                </li>
              </ul>
            </div>
          </div>
          <div :if={@vault_candidates != []} class="link-project-panel">
            <p class="link-project-panel-title">Config files to import</p>
            <.modal_hint>
              Uses .gitignore when present to surface ignored files (for example .env.local). Tap a row to include or exclude it.
            </.modal_hint>
            <ul class="link-candidates">
              <li :for={{c, idx} <- Enum.with_index(@vault_candidates)}>
                <button
                  type="button"
                  phx-click="link_project_vault_toggle"
                  phx-value-path={c.relative_path}
                  id={"link-project-vault-candidate-#{idx}"}
                  class={[
                    "link-candidate",
                    Map.get(@vault_selected, c.relative_path, true) && "is-selected"
                  ]}
                >
                  <span class="link-candidate-path">{c.relative_path}</span>
                  <span class="link-candidate-meta">
                    <span
                      :if={c.gitignored}
                      class="pill warn"
                      style="font-size: 10px; padding: 2px 6px"
                    >
                      gitignored
                    </span>
                    <span class={note_type_badge_class(c.note_type)}>
                      {note_type_badge_label(c.note_type)}
                    </span>
                    <.icon
                      name={
                        if(Map.get(@vault_selected, c.relative_path, true),
                          do: "check",
                          else: "minus"
                        )
                      }
                      size={14}
                    />
                  </span>
                </button>
              </li>
            </ul>
            <p class="link-project-callout">
              Checked files are imported as vault items when you confirm.
            </p>
          </div>
        </div>
        <div :if={@pro_plan? and @stage == :preview} class="modal-field" style="margin-top: 12px">
          <form id="link-project-sentinel-form" phx-change="link_project_sentinel_change">
            <label
              for="link-project-run-sentinel"
              style="display: flex; align-items: flex-start; gap: 8px; cursor: pointer"
            >
              <input
                type="checkbox"
                name="run_sentinel_scan"
                id="link-project-run-sentinel"
                value="true"
                checked={@run_sentinel_scan}
                style="margin-top: 2px"
              />
              <span>
                <span style="font-weight: 500; color: var(--ink)">Run Security Sentinel Scan</span>
                <span class="modal-hint" style="display: block; margin-top: 4px">
                  You can always run the scan anytime from the Project Details view.
                </span>
              </span>
            </label>
          </form>
        </div>
      </.modal_body>
      <.modal_foot :if={@stage == :preview} class={@folder_has_items && "modal-foot--split"}>
        <form
          :if={@folder_has_items}
          id="link-project-existing-notes-form"
          phx-change="link_project_existing_notes_change"
          class="modal-field"
          style="flex: 1; min-width: 14rem; max-width: 28rem; margin: 0"
        >
          <.modal_label for="link-project-existing-notes">
            If a matching vault item already exists in this project
          </.modal_label>
          <select id="link-project-existing-notes" name="existing_notes">
            <option value="" selected={is_nil(@existing_notes_strategy)} disabled>
              Choose an option…
            </option>
            <option value="overwrite" selected={@existing_notes_strategy == "overwrite"}>
              Overwrite existing vault items
            </option>
            <option value="duplicate" selected={@existing_notes_strategy == "duplicate"}>
              Create duplicate vault items
            </option>
          </select>
        </form>
        <div class="foot-actions">
          <button type="button" phx-click="cancel_link_project_modal" class="btn sm">
            Cancel
          </button>
          <button
            type="button"
            id="link-project-confirm-button"
            phx-click="confirm_link_project"
            class="btn sm primary"
          >
            Confirm
          </button>
        </div>
      </.modal_foot>
    </.modal_shell>
    """
  end
end
