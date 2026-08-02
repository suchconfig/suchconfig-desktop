defmodule SuchConfigDesktopWeb.Components.ProjectVault.NewNote do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting

  attr :show, :boolean, default: false
  attr :vault_item_ui_enabled?, :boolean, default: false
  attr :note_category, :string, default: "generic_note"
  attr :note_title, :string, default: ""
  attr :note_raw_content, :string, default: ""
  attr :new_note_tags, :string, default: ""
  attr :selected_folder_id, :any, default: nil

  def new_note_modal(assigns) do
    modal_type = Formatting.modal_type_id(assigns.note_category, assigns.vault_item_ui_enabled?)

    assigns =
      assigns
      |> assign(:modal_type, modal_type)
      |> assign(:type_options, Formatting.modal_type_options(assigns.vault_item_ui_enabled?))
      |> assign(:title_placeholder, Formatting.new_note_title_placeholder(modal_type))

    ~H"""
    <.modal_shell show={@show} id="new-note-modal" on_cancel="close_new_note_modal">
      <.modal_head title="New note" on_close="close_new_note_modal" />
      <.form
        for={%{}}
        id="new-note-form"
        phx-change="update_note_form"
        phx-submit="save_note"
        class="modal-form"
      >
        <input type="hidden" name="note_category" value={@note_category} />
        <.modal_body>
          <div class="field">
            <div class="field-label"><span>Type</span></div>
            <div class="type-grid">
              <button
                :for={option <- @type_options}
                type="button"
                phx-click="set_new_note_category"
                phx-value-type={option.id}
                id={"new-note-type-#{option.id}"}
                class={["type-card", @modal_type == option.id && "active"]}
              >
                <span class="glyph"><.icon name={option.icon} size={14} /></span>
                <span class="t">{option.label}</span>
                <span class="d">{option.desc}</span>
              </button>
            </div>
          </div>

          <.modal_text_field
            id="new-note-title-input"
            name="note_title"
            label="Title"
            value={@note_title}
            placeholder={@title_placeholder}
          />

          <div class="field">
            <div class="field-label"><span>Contents</span></div>
            <div class="field-row">
              <textarea
                id="new-note-content-input"
                name="note_raw_content"
                rows={8}
                placeholder={Formatting.note_content_placeholder(@note_category)}
              >{@note_raw_content}</textarea>
            </div>
          </div>

          <div class="field">
            <div class="field-label"><span>Tags</span></div>
            <div class="field-row plain">
              <input
                type="text"
                id="new-note-tags-input"
                name="new_note_tags"
                value={@new_note_tags}
                placeholder="add tags, comma separated"
              />
            </div>
          </div>
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="close_new_note_modal" class="btn ghost">
            Cancel
          </button>
          <button type="submit" id="new-note-save-button" class="btn primary">
            <.icon name="lock" size={13} /> Seal & save
          </button>
        </.modal_foot>
      </.form>
    </.modal_shell>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :placeholder, :string, default: nil

  defp modal_text_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label"><span>{@label}</span></div>
      <div class="field-row plain">
        <input
          type="text"
          id={@id}
          name={@name}
          value={@value}
          placeholder={@placeholder}
        />
      </div>
    </div>
    """
  end
end
