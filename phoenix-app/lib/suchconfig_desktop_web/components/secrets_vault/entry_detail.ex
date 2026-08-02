defmodule SuchConfigDesktopWeb.Components.SecretsVault.EntryDetail do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon
  import SuchConfigDesktopWeb.Sc.Pill

  alias SuchConfigDesktop.SecretsVault.KindFields
  alias SuchConfigDesktopWeb.Components.ProjectVault.NoteEditor
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting

  attr :global_passkey_unlocked, :boolean, required: true
  attr :folders, :list, default: []
  attr :entry_folder_id, :any, default: nil
  attr :item_title, :string, default: ""
  attr :item_kind, :string, default: "password"
  attr :username, :string, default: ""
  attr :url, :string, default: ""
  attr :public_key, :string, default: ""
  attr :fingerprint, :string, default: ""
  attr :secret_body, :string, default: ""
  attr :show_secret, :boolean, default: false
  attr :selected_item_id, :any, default: nil
  attr :item_inserted_at, :any, default: nil
  attr :item_updated_at, :any, default: nil
  attr :generator_strength, :any, default: nil
  attr :crdt_enabled?, :boolean, default: false
  attr :generator_event_target, :string, default: nil
  attr :item_tags, :list, default: []
  attr :tag_suggestions, :list, default: []

  def entry_detail(assigns) do
    kind = Formatting.normalize_kind(assigns.item_kind)

    assigns =
      assigns
      |> assign(:kind, kind)
      |> assign(:detail_icon, Formatting.detail_icon_name(kind))
      |> assign(:body_label, KindFields.body_label(kind))
      |> assign(:body_multiline?, KindFields.body_multiline?(kind))
      |> assign(:body_masked?, KindFields.body_masked?(kind))
      |> assign(:shows_generator?, KindFields.shows_generator?(kind))
      |> assign(:shows_username?, KindFields.shows_username?(kind))
      |> assign(:username_label, username_label(kind))
      |> assign(:shows_url?, KindFields.shows_url?(kind))
      |> assign(:url_label, KindFields.url_label(kind))
      |> assign(:shows_ssh_fields?, KindFields.shows_ssh_fields?(kind))
      |> assign(:strength_label, Formatting.strength_label(assigns.generator_strength))
      |> assign(:strength_color, Formatting.strength_color(assigns.generator_strength))
      |> assign(:glyph_type, Formatting.glyph_type(kind))
      |> assign(:created_label, Formatting.format_date(assigns.item_inserted_at))
      |> assign(:modified_label, Formatting.format_relative_time(assigns.item_updated_at))
      |> assign(:entry_folder_name, entry_folder_name(assigns.folders, assigns.entry_folder_id))

    ~H"""
    <div class="detail" id="secrets-entry-detail">
      <div :if={!@global_passkey_unlocked} class="vault-unlock">
        <.icon name="lock" size={28} />
        <p class="muted" style="margin-top: 12px">Unlock the vault to view or edit secrets.</p>
      </div>

      <div :if={@global_passkey_unlocked}>
        <form
          :if={@selected_item_id}
          id="secrets-entry-tag-picker-form"
          phx-submit="add_item_tag_from_input"
          hidden
        />
        <.form
          for={%{}}
          id="secrets-entry-form"
          phx-change="entry_form_change"
          phx-submit="save_item"
        >
          <div class="detail-head">
            <div class="icon-lg" data-t={@glyph_type}>
              <.icon name={@detail_icon} size={22} />
            </div>
            <div style="min-width: 0; flex: 1">
              <input
                type="text"
                id="secret-title-input"
                name="title"
                value={@item_title}
                placeholder="Untitled entry"
                class="detail-title-input"
                autocomplete="off"
                autocorrect="off"
                autocapitalize="none"
                spellcheck="false"
              />
              <div class="subline">
                <.pill tone="ok">{Formatting.detail_pill_label(@kind)}</.pill>
                <span :if={@item_tags != []}>·</span>
                <span
                  :for={tag <- @item_tags}
                  class="tag"
                  style="font-size: 11px; padding: 2px 8px"
                >
                  {tag}
                  <button
                    type="button"
                    phx-click="remove_item_tag"
                    phx-value-tag={tag}
                    class="btn xs icon-only"
                    style="margin-left: 4px; padding: 0; width: 14px; height: 14px; vertical-align: -2px"
                    aria-label={"Remove tag #{tag}"}
                  >
                    <.icon name="x" size={10} />
                  </button>
                </span>
                <span :if={@item_tags != []}>·</span>
                <span>
                  <.icon name="vault" size={12} style="vertical-align: -2px; margin-right: 4px" />
                  {@entry_folder_name}
                </span>
                <span>·</span>
                <span>
                  <.icon name="clock" size={12} style="vertical-align: -2px; margin-right: 4px" />
                  edited {@modified_label}
                </span>
              </div>
            </div>
            <div class="actions">
              <button type="button" class="btn sm icon-only" title="History" disabled>
                <.icon name="history" size={14} />
              </button>
              <NoteEditor.item_tag_picker
                :if={@selected_item_id}
                id="secrets-entry-tag-picker"
                form_target_id="secrets-entry-tag-picker-form"
                title="Tags"
                item_tags={@item_tags}
                tag_suggestions={@tag_suggestions}
              />
              <button type="button" class="btn sm icon-only" title="More" disabled>
                <.icon name="more" size={14} />
              </button>
            </div>
          </div>

          <div class="meta-strip">
            <div class="meta-cell">
              <div class="k">Strength</div>
              <div class="v" style={"color: #{@strength_color}"}>{@strength_label}</div>
            </div>
            <div class="meta-cell">
              <div class="k">Created</div>
              <div class="v">{@created_label}</div>
            </div>
            <div class="meta-cell">
              <div class="k">Last used</div>
              <div class="v">{@modified_label}</div>
            </div>
            <div class="meta-cell">
              <div class="k">Devices</div>
              <div class="v">{if @crdt_enabled?, do: "3 · synced", else: "local"}</div>
            </div>
          </div>

          <div class="detail-body">
            <div class="field">
              <div class="field-label"><span>Folder</span></div>
              <div class="new-entry-folder-row">
                <select
                  name="secrets_vault_folder_id"
                  id="entry-detail-folder-select"
                  class="new-entry-folder-select"
                  phx-change="entry_form_change"
                >
                  <option
                    :for={folder <- @folders}
                    value={folder.id}
                    selected={folder.id == @entry_folder_id}
                  >
                    {folder.name}
                  </option>
                </select>
                <button
                  type="button"
                  phx-click="open_new_folder_modal"
                  id="entry-detail-folder-button"
                  class="btn xs icon-only"
                  title="New folder"
                  aria-label="New folder"
                >
                  <.icon name="folder-plus" size={14} />
                </button>
              </div>
            </div>

            <div :if={@shows_username?}>
              <.form_text_field
                id="secret-username-input"
                name="username"
                label={@username_label}
                value={@username}
                copy_event="copy_username"
                copy_button_id="copy-username-button"
              />
            </div>

            <div :if={@shows_url?}>
              <.form_text_field
                id="secret-url-input"
                name="url"
                label={@url_label}
                value={@url}
                mono
              />
            </div>

            <div :if={@shows_ssh_fields?}>
              <.form_text_field
                id="secret-public-key-input"
                name="public_key"
                label="Public key"
                value={@public_key}
                multiline
                copy_event="copy_public_key"
                copy_button_id="copy-public-key-button"
              />
              <.form_text_field
                id="secret-fingerprint-input"
                name="fingerprint"
                label="Fingerprint"
                value={@fingerprint}
                mono
                copy_event="copy_fingerprint"
                copy_button_id="copy-fingerprint-button"
              />
            </div>

            <.form_secret_field
              id="secret-body-input"
              name="secret_body"
              label={secret_field_label(@kind, @body_label)}
              value={@secret_body}
              multiline={@body_multiline?}
              masked={@body_masked?}
              show_secret={@show_secret}
              shows_generator?={@shows_generator?}
              generator_event_target={@generator_event_target}
            />

            <div class="field">
              <div class="field-label" style="margin-bottom: 6px">
                <span>Activity</span>
                <span class="faint" style="text-transform: none; letter-spacing: 0; font-size: 11px">
                  local audit log · never leaves device
                </span>
              </div>
              <div class="audit">
                <div class="audit-row copy">
                  <span class="blip" />
                  <span class="when">2m ago</span>
                  <span class="what">Copied password</span>
                  <span class="where">macbook-air · local</span>
                </div>
                <div class="audit-row edit">
                  <span class="blip" />
                  <span class="when">3h ago</span>
                  <span class="what">Updated URL</span>
                  <span class="where">macbook-air · local</span>
                </div>
                <div class="audit-row copy">
                  <span class="blip" />
                  <span class="when">yesterday</span>
                  <span class="what">Copied username</span>
                  <span class="where">studio-mini · local</span>
                </div>
                <div class="audit-row edit">
                  <span class="blip" />
                  <span class="when">{@modified_label}</span>
                  <span class="what">Rotated password</span>
                  <span class="where">macbook-air · local</span>
                </div>
                <div class="audit-row create">
                  <span class="blip" />
                  <span class="when">{@created_label}</span>
                  <span class="what">Created entry</span>
                  <span class="where">macbook-air · local</span>
                </div>
              </div>
            </div>
          </div>

          <div class="detail-footer">
            <label class="detail-kind-select">
              <span>Type</span>
              <select id="secret-kind-select" name="kind">
                <option
                  :for={{value, label} <- Formatting.kind_options()}
                  value={value}
                  selected={@kind == value}
                >
                  {label}
                </option>
              </select>
            </label>
            <div class="detail-footer-actions">
              <button
                :if={@selected_item_id}
                type="button"
                phx-click="open_delete_modal"
                id="delete-secret-button"
                class="btn sm danger"
                title="Delete"
              >
                Delete
              </button>
              <button type="submit" id="save-secret-button" class="btn sm primary" title="Save">
                Save
              </button>
            </div>
          </div>
        </.form>
      </div>
    </div>
    """
  end

  defp entry_folder_name(folders, folder_id) do
    Enum.find_value(folders, "Vault", fn folder ->
      if folder.id == folder_id, do: folder.name
    end)
  end

  defp username_label("api_key"), do: "Environment"
  defp username_label(kind), do: KindFields.username_label(kind)

  defp secret_field_label("api_key", _body), do: "Token"
  defp secret_field_label("ssh_key", _body), do: "Passphrase"
  defp secret_field_label("secure_note", _body), do: "Sealed contents"
  defp secret_field_label(_, body), do: body

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :mono, :boolean, default: false
  attr :multiline, :boolean, default: false
  attr :copy_event, :string, default: nil
  attr :copy_button_id, :string, default: nil

  defp form_text_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label"><span>{@label}</span></div>
      <div class={["field-row", !@mono && !@multiline && "plain"]}>
        <%= if @multiline do %>
          <textarea id={@id} name={@name} rows={5}>{@value}</textarea>
        <% else %>
          <input type="text" id={@id} name={@name} value={@value} />
        <% end %>
        <button
          :if={@copy_event}
          type="button"
          id={@copy_button_id}
          phx-hook="CopyButton"
          data-copy-text={@value}
          data-copy-event={@copy_event}
          class="field-btn"
          title="Copy"
        >
          <.icon name="copy" size={14} />
        </button>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :name, :string, required: true
  attr :label, :string, required: true
  attr :value, :string, default: ""
  attr :multiline, :boolean, default: false
  attr :masked, :boolean, default: true
  attr :show_secret, :boolean, default: false
  attr :shows_generator?, :boolean, default: false
  attr :generator_event_target, :string, default: nil

  defp form_secret_field(assigns) do
    ~H"""
    <div class="field">
      <div class="field-label">
        <span>{@label}</span>
        <span
          class="faint"
          style="text-transform: none; letter-spacing: 0; font-family: var(--font-mono); font-size: 11px"
        >
          {if @show_secret || !@masked,
            do: "#{String.length(@value)} chars",
            else: "#{String.length(@value)} chars · hidden"}
        </span>
      </div>
      <div class={["field-row secret", !@show_secret && @masked && "masked"]}>
        <%= if @multiline do %>
          <textarea id={@id} name={@name} rows={8}>{@value}</textarea>
        <% else %>
          <input
            type={if @masked && !@show_secret, do: "password", else: "text"}
            id={@id}
            name={@name}
            value={@value}
          />
        <% end %>
        <button
          :if={@masked}
          type="button"
          phx-click="toggle_reveal"
          id="toggle-reveal-button"
          class="field-btn"
          title={if @show_secret, do: "Hide", else: "Reveal"}
        >
          <.icon name={if @show_secret, do: "eye-off", else: "eye"} size={14} />
        </button>
        <button
          :if={@shows_generator?}
          type="button"
          phx-click="open_generator_drawer"
          phx-value-context="secrets_entry"
          phx-value-target="password"
          phx-target={@generator_event_target}
          id="open-generator-button"
          class="field-btn"
          title="Generate"
        >
          <.icon name="wand" size={14} />
        </button>
        <button
          type="button"
          id="copy-secret-button"
          phx-hook="CopyButton"
          data-copy-text={@value}
          data-copy-event="copy_secret"
          class="field-btn"
          title="Copy"
        >
          <.icon name="copy" size={14} />
        </button>
      </div>
    </div>
    """
  end
end
