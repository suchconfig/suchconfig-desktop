defmodule SuchConfigDesktopWeb.Components.SecretsVault.Modals do
  @moduledoc false

  use SuchConfigDesktopWeb, :html

  attr :show, :boolean, default: false

  def new_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="new-secrets-folder-modal"
      on_cancel="close_new_folder_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head title="New folder" on_close="close_new_folder_modal" />
      <.form for={%{}} phx-submit="create_folder" id="new-secrets-folder-form" class="modal-form">
        <.modal_body>
          <input type="text" name="folder[name]" placeholder="Folder name" required />
          <input type="text" name="folder[description]" placeholder="Description (optional)" />
        </.modal_body>
        <.modal_foot>
          <button type="button" phx-click="close_new_folder_modal" class="btn sm">
            Cancel
          </button>
          <button type="submit" class="btn sm primary">
            Create
          </button>
        </.modal_foot>
      </.form>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false
  attr :edit_folder_name, :string, default: ""
  attr :edit_folder_description, :string, default: ""
  attr :edit_folder_delete_confirm, :boolean, default: false

  def edit_folder_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="edit-secrets-folder-modal"
      on_cancel="close_edit_folder_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head
        title={if @edit_folder_delete_confirm, do: "Delete folder?", else: "Edit folder"}
        on_close="close_edit_folder_modal"
      />
      <%= if @edit_folder_delete_confirm do %>
        <.modal_body>
          <.modal_hint>
            Are you sure you want to delete <span class="strong">{@edit_folder_name}</span>? This cannot be undone.
          </.modal_hint>
          <.modal_hint>Entries in this folder will be unassigned from the folder.</.modal_hint>
        </.modal_body>
        <.modal_foot>
          <button
            type="button"
            phx-click="cancel_delete_folder_confirm"
            id="edit-secrets-folder-delete-back"
            class="btn sm"
          >
            Back
          </button>
          <button
            type="button"
            phx-click="delete_folder"
            id="edit-secrets-folder-delete-confirm"
            class="btn sm danger"
          >
            Delete folder
          </button>
        </.modal_foot>
      <% else %>
        <.form for={%{}} phx-submit="update_folder" id="edit-secrets-folder-form" class="modal-form">
          <.modal_body>
            <input
              type="text"
              name="folder[name]"
              value={@edit_folder_name}
              placeholder="Folder name"
              required
            />
            <input
              type="text"
              name="folder[description]"
              value={@edit_folder_description}
              placeholder="Description (optional)"
            />
          </.modal_body>
          <.modal_foot class="modal-foot--split">
            <button
              type="button"
              phx-click="request_delete_folder"
              id="edit-secrets-folder-delete"
              class="btn sm danger"
              aria-label="Delete folder"
            >
              Delete
            </button>
            <div class="foot-actions">
              <button type="button" phx-click="close_edit_folder_modal" class="btn sm">
                Cancel
              </button>
              <button type="submit" class="btn sm primary">
                Save
              </button>
            </div>
          </.modal_foot>
        </.form>
      <% end %>
    </.modal_shell>
    """
  end

  attr :show, :boolean, default: false

  def delete_modal(assigns) do
    ~H"""
    <.modal_shell
      show={@show}
      id="delete-secret-modal"
      on_cancel="close_delete_modal"
      size="sm"
      class="overlay--stack"
    >
      <.modal_head title="Delete entry?" on_close="close_delete_modal" />
      <.modal_body>
        <.modal_hint>This cannot be undone.</.modal_hint>
      </.modal_body>
      <.modal_foot>
        <button type="button" phx-click="close_delete_modal" class="btn sm">
          Cancel
        </button>
        <button type="button" phx-click="confirm_delete" class="btn sm danger">
          Delete
        </button>
      </.modal_foot>
    </.modal_shell>
    """
  end
end
