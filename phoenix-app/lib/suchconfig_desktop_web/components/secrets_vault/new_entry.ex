defmodule SuchConfigDesktopWeb.Components.SecretsVault.NewEntry do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Modal

  alias SuchConfigDesktop.SecretsVault.Folder
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting

  attr :show, :boolean, default: false
  attr :folders, :list, default: []
  attr :new_entry_folder_id, :any, default: nil
  attr :item_kind, :string, default: "password"
  attr :item_title, :string, default: ""
  attr :username, :string, default: ""
  attr :url, :string, default: ""
  attr :fingerprint, :string, default: ""
  attr :secret_body, :string, default: ""
  attr :show_secret, :boolean, default: false
  attr :new_entry_tags, :string, default: ""
  attr :generator_event_target, :string, default: nil

  def new_entry_modal(assigns) do
    modal_type = Formatting.modal_type_id(assigns.item_kind)

    picker_folders =
      Enum.reject(assigns.folders, &(&1.name == Folder.unassociated_name()))

    assigns =
      assigns
      |> assign(:modal_type, modal_type)
      |> assign(:title_placeholder, Formatting.new_entry_title_placeholder(modal_type))
      |> assign(:picker_folders, picker_folders)
      |> assign(:unassociated_selected?, is_nil(assigns.new_entry_folder_id))

    ~H"""
    <.modal_shell show={@show} id="new-entry-modal" on_cancel="close_new_entry_modal">
      <.modal_head title="New entry" on_close="close_new_entry_modal" />
      <.form
        for={%{}}
        id="new-entry-form"
        phx-hook="NewEntryTypePicker"
        phx-change="entry_form_change"
        phx-submit="save_item"
        class="modal-form"
      >
        <input type="hidden" name="kind" value={@item_kind} />
        <.modal_body>
          <div class="field">
            <div class="field-label"><span>Type</span></div>
            <div class="type-grid">
              <button
                :for={option <- Formatting.modal_type_options()}
                type="button"
                phx-click="set_new_entry_kind"
                phx-value-type={option.id}
                id={"new-entry-type-#{option.id}"}
                class={["type-card", @modal_type == option.id && "active"]}
              >
                <span class="glyph"><.icon name={option.icon} size={14} /></span>
                <span class="t">{option.label}</span>
                <span class="d">{option.desc}</span>
              </button>
            </div>
          </div>

          <.modal_text_field
            id="new-entry-title-input"
            name="title"
            label="Title"
            value={@item_title}
            placeholder={@title_placeholder}
            autocomplete="off"
            autocapitalize="none"
          />

          <div :if={@modal_type == "login"} class="entry-type-panel" data-entry-type="login">
            <div class="field">
              <div class="field-label">
                <span>Username</span>
                <button
                  type="button"
                  phx-click="open_generator_drawer"
                  phx-value-context="secrets_entry"
                  phx-value-target="username"
                  phx-target={@generator_event_target}
                  id="new-entry-generate-username-button"
                  class="btn xs ghost"
                >
                  <.icon name="wand" size={11} /> generate
                </button>
              </div>
              <div class="field-row plain">
                <input
                  type="text"
                  id="new-entry-username-input"
                  name="username"
                  value={@username}
                  placeholder="[email protected]"
                />
              </div>
            </div>
            <div class="field">
              <div class="field-label">
                <span>Password</span>
                <button
                  type="button"
                  phx-click="open_generator_drawer"
                  phx-value-context="secrets_entry"
                  phx-value-target="password"
                  phx-target={@generator_event_target}
                  id="new-entry-generate-button"
                  class="btn xs ghost"
                >
                  <.icon name="wand" size={11} /> generate
                </button>
              </div>
              <div class={["field-row secret", !@show_secret && "masked"]}>
                <input
                  type={if @show_secret, do: "text", else: "password"}
                  id="new-entry-password-input"
                  name="secret_body"
                  value={@secret_body}
                  placeholder="paste or generate"
                />
                <button
                  type="button"
                  phx-click="toggle_reveal"
                  id="new-entry-toggle-reveal-button"
                  class="field-btn"
                  title={if @show_secret, do: "Hide", else: "Reveal"}
                >
                  <.icon name={if @show_secret, do: "eye-off", else: "eye"} size={14} />
                </button>
              </div>
            </div>
            <.modal_text_field
              id="new-entry-url-input"
              name="url"
              label="Website URL"
              value={@url}
              placeholder="https://"
            />
          </div>

          <div :if={@modal_type == "api"} class="entry-type-panel" data-entry-type="api">
            <.modal_text_field
              id="new-entry-environment-input"
              name="username"
              label="Environment"
              value={@username}
              placeholder="production · staging · dev"
            />
            <div class="field">
              <div class="field-label"><span>Token</span></div>
              <div class="field-row">
                <textarea
                  id="new-entry-token-input"
                  name="secret_body"
                  rows={3}
                  placeholder="sk-…"
                >{@secret_body}</textarea>
              </div>
            </div>
          </div>

          <div :if={@modal_type == "ssh"} class="entry-type-panel" data-entry-type="ssh">
            <.modal_text_field
              id="new-entry-fingerprint-input"
              name="fingerprint"
              label="Fingerprint"
              value={@fingerprint}
              placeholder="SHA256:…"
              mono
            />
            <div class="field">
              <div class="field-label"><span>Private key</span></div>
              <div class="field-row">
                <textarea
                  id="new-entry-private-key-input"
                  name="secret_body"
                  rows={4}
                  placeholder="-----BEGIN OPENSSH PRIVATE KEY-----"
                >{@secret_body}</textarea>
              </div>
            </div>
            <.modal_text_field
              id="new-entry-passphrase-input"
              name="ssh_passphrase"
              label="Passphrase"
              value=""
              placeholder="optional"
            />
          </div>

          <div :if={@modal_type == "note"} class="entry-type-panel" data-entry-type="note">
            <div class="field-label"><span>Contents</span></div>
            <div class="field-row">
              <textarea
                id="new-entry-note-input"
                name="secret_body"
                rows={6}
                placeholder="# markdown supported\n\nThe contents are sealed before they touch disk."
              >{@secret_body}</textarea>
            </div>
          </div>

          <div class="field">
            <div class="field-label"><span>Folder</span></div>
            <div class="new-entry-folder-row">
              <select
                name="secrets_vault_folder_id"
                id="new-entry-folder-select"
                class="new-entry-folder-select"
              >
                <option value="" selected={@unassociated_selected?}>Unassociated</option>
                <option
                  :for={folder <- @picker_folders}
                  value={folder.id}
                  selected={folder.id == @new_entry_folder_id}
                >
                  {folder.name}
                </option>
              </select>
              <button
                type="button"
                phx-click="open_new_folder_modal"
                id="new-entry-folder-button"
                class="btn xs icon-only"
                title="New folder"
                aria-label="New folder"
              >
                <.icon name="folder-plus" size={14} />
              </button>
            </div>
          </div>

          <div class="field">
            <div class="field-label"><span>Tags</span></div>
            <div class="field-row plain">
              <input
                type="text"
                id="new-entry-tags-input"
                name="new_entry_tags"
                value={@new_entry_tags}
                placeholder="add tags, comma separated"
              />
            </div>
          </div>
        </.modal_body>
        <.modal_foot>
          <div class="pt-2 pr-6">
            <button type="button" phx-click="close_new_entry_modal" class="btn ghost">
              Cancel
            </button>
            <button type="submit" id="new-entry-save-button" class="btn primary">
              <.icon name="lock" size={13} /> Seal & save
            </button>
          </div>
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
  attr :mono, :boolean, default: false
  attr :autocomplete, :string, default: nil
  attr :autocapitalize, :string, default: nil

  defp modal_text_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label"><span>{@label}</span></div>
      <div class={["field-row", !@mono && "plain"]}>
        <input
          type="text"
          id={@id}
          name={@name}
          value={@value}
          placeholder={@placeholder}
          autocomplete={@autocomplete}
          autocapitalize={@autocapitalize}
        />
      </div>
    </div>
    """
  end
end
