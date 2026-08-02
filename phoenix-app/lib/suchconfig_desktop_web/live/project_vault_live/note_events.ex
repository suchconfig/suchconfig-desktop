defmodule SuchConfigDesktopWeb.ProjectVaultLive.NoteEvents do
  @moduledoc """
  Event handlers for secure note creation, editing, unlocking, deletion, and
  clipboard helpers. All handlers accept `(params, socket)` and return
  `{:noreply, socket}`.
  """

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3]

  alias SuchConfigDesktop.ProjectVault

  alias SuchConfigDesktopWeb.ProjectVaultLive.FolderEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey

  def close_new_note_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_new_note_modal: false,
       new_note_form_highlight: false,
       new_note_tags: ""
     )}
  end

  def set_new_note_category(%{"type" => type}, socket) when is_binary(type) do
    category = Formatting.kind_from_modal_type(type, socket.assigns.vault_item_ui_enabled?)

    {:noreply,
     assign(socket,
       note_category: category,
       vault_item_kind: category
     )}
  end

  def new(params, socket) do
    if socket.assigns[:vault_item_ui_enabled?] do
      VaultItemEvents.new_vault_item_draft(params, socket)
    else
      new_legacy_note(params, socket)
    end
  end

  defp new_legacy_note(params, socket) do
    socket =
      case Map.get(params, "project_folder_id") do
        id when is_binary(id) and id != "" ->
          case Integer.parse(id) do
            {folder_id, ""} when folder_id != socket.assigns.selected_folder_id ->
              case FolderEvents.select(%{"id" => id}, socket) do
                {:noreply, s} -> s
              end

            _ ->
              socket
          end

        _ ->
          socket
      end

    {:noreply, assign(socket, new_note_draft_assigns(editor_focus: :note, note_unlocked: false))}
  end

  defp new_note_draft_assigns(extra) do
    Keyword.merge(
      [
        selected_note_id: nil,
        selected_vault_item_id: nil,
        editor_focus: :note,
        note_unlocked: false,
        note_category: "generic_note",
        vault_item_kind: "generic_note",
        security_mode: "global_passkey",
        note_title: "",
        note_raw_content: "",
        item_tags: [],
        display_mode: :input,
        copy_all_copied: false,
        env_var_value_copied: %{},
        env_var_all_copied: %{},
        info: nil,
        error: nil,
        show_new_note_modal: true,
        new_note_form_highlight: false,
        new_note_tags: ""
      ],
      extra
    )
  end

  def set_display_mode(%{"mode" => mode}, socket) do
    if Formatting.env_display_mode?(socket.assigns.note_category, socket.assigns[:item_tags]) do
      mode_atom =
        case mode do
          "copy" -> :copy
          _ -> :input
        end

      {:noreply, assign(socket, display_mode: mode_atom)}
    else
      {:noreply, assign(socket, display_mode: :input)}
    end
  end

  def set_category(%{"note_category" => note_category}, socket) do
    if socket.assigns[:editor_focus] == :vault_item &&
         Formatting.project_details_vault_item?(
           socket.assigns.note_title,
           socket.assigns.note_category
         ) do
      {:noreply, socket}
    else
      normalized =
        if socket.assigns[:editor_focus] == :vault_item do
          Formatting.normalize_vault_item_kind(note_category)
        else
          Formatting.normalize_note_type(note_category)
        end

      {:noreply,
       assign(socket,
         note_category: normalized,
         vault_item_kind: normalized,
         display_mode:
           env_display_mode_after_category_change(
             socket.assigns.note_category,
             normalized,
             socket.assigns[:item_tags],
             socket.assigns.display_mode
           )
       )}
    end
  end

  defp env_display_mode_after_category_change(
         previous_category,
         next_category,
         tags,
         current_mode
       ) do
    was_env? = Formatting.env_display_mode?(previous_category, tags)
    now_env? = Formatting.env_display_mode?(next_category, tags)

    cond do
      now_env? and not was_env? -> :copy
      now_env? -> current_mode
      true -> :input
    end
  end

  def update_form(params, socket) do
    note_title = Map.get(params, "note_title", socket.assigns.note_title) |> String.trim()
    note_raw_content = Map.get(params, "note_raw_content", socket.assigns.note_raw_content)

    note_category =
      cond do
        socket.assigns[:editor_focus] != :vault_item ->
          Formatting.normalize_note_type(
            Map.get(params, "note_category", socket.assigns.note_category)
          )

        Formatting.project_details_vault_title?(note_title) ->
          "guideline"

        true ->
          Formatting.normalize_vault_item_kind(
            Map.get(params, "note_category", socket.assigns.note_category)
          )
      end

    was_env? =
      Formatting.env_display_mode?(socket.assigns.note_category, socket.assigns[:item_tags])

    now_env? = Formatting.env_display_mode?(note_category, socket.assigns[:item_tags])

    display_mode =
      cond do
        now_env? and not was_env? -> :copy
        now_env? -> socket.assigns.display_mode
        true -> :input
      end

    {:noreply,
     assign(socket,
       note_title: note_title,
       note_raw_content: note_raw_content,
       note_category: note_category,
       vault_item_kind: note_category,
       security_mode: "global_passkey",
       global_passkey_unlocked: socket.assigns.global_passkey_unlocked,
       vault_password: socket.assigns.vault_password,
       show_global_passkey_modal: false,
       global_passkey_input: "",
       global_passkey_purpose: nil,
       display_mode: display_mode,
       error: nil,
       info: nil,
       new_note_tags: Map.get(params, "new_note_tags", socket.assigns[:new_note_tags] || "")
     )}
  end

  def select(%{"id" => id}, socket) do
    socket = VaultKey.ensure_vault_key_from_registry(socket)
    note_id = String.to_integer(id)
    note = ProjectVault.get_note!(note_id)
    note_category = Formatting.normalize_note_type(note.note_type)
    current_password = socket.assigns.vault_password

    case VaultKey.decrypt_note_content(note, current_password) do
      {:ok, raw_content} ->
        {:noreply,
         assign(socket,
           selected_note_id: note.id,
           selected_vault_item_id: nil,
           editor_focus: :note,
           note_unlocked: true,
           note_category: note_category,
           vault_item_kind: note_category,
           note_title: note.title,
           note_raw_content: raw_content,
           display_mode: Formatting.default_display_mode(note_category),
           copy_all_copied: false,
           env_var_value_copied: %{},
           env_var_all_copied: %{},
           decrypt_failed_wrong_key: false,
           pending_unlock_note_id: nil,
           pending_unlock_note_title: "",
           info: nil,
           error: nil,
           new_note_form_highlight: false
         )}

      {:error, :missing_password} ->
        {:noreply,
         assign(socket,
           selected_note_id: note.id,
           selected_vault_item_id: nil,
           editor_focus: :note,
           note_unlocked: false,
           note_category: note_category,
           vault_item_kind: note_category,
           note_title: note.title,
           note_raw_content: "",
           show_global_passkey_modal: true,
           global_passkey_input: "",
           global_passkey_purpose: "unlock",
           pending_unlock_note_id: note.id,
           pending_unlock_note_title: note.title,
           decrypt_failed_wrong_key: false,
           info: nil,
           error: nil,
           new_note_form_highlight: false
         )}

      {:error, _} ->
        if VaultKey.session_global_passkey_unlocked?(socket) do
          {:noreply,
           assign(socket,
             selected_note_id: note.id,
             selected_vault_item_id: nil,
             editor_focus: :note,
             note_unlocked: false,
             note_category: note_category,
             vault_item_kind: note_category,
             note_title: note.title,
             note_raw_content: "",
             pending_unlock_note_id: note.id,
             pending_unlock_note_title: note.title,
             decrypt_failed_wrong_key: true,
             info: nil,
             error: "This note could not be decrypted with the current passkey.",
             new_note_form_highlight: false
           )}
        else
          {:noreply,
           assign(socket,
             selected_note_id: note.id,
             selected_vault_item_id: nil,
             editor_focus: :note,
             note_unlocked: false,
             note_category: note_category,
             vault_item_kind: note_category,
             note_title: note.title,
             note_raw_content: "",
             show_global_passkey_modal: true,
             global_passkey_input: "",
             global_passkey_purpose: "unlock",
             pending_unlock_note_id: note.id,
             pending_unlock_note_title: note.title,
             info: nil,
             error: "Global Passkey required to unlock this note.",
             new_note_form_highlight: false
           )}
        end
    end
  end

  def save(params, socket) do
    if socket.assigns[:editor_focus] == :vault_item do
      VaultItemEvents.save_vault_item_document(params, socket)
    else
      save_legacy_note(params, socket)
    end
  end

  defp save_legacy_note(params, socket) do
    socket = VaultKey.ensure_vault_key_from_registry(socket)
    selected_folder_id = socket.assigns.selected_folder_id
    note_title_from_params = Map.get(params, "note_title", "") |> String.trim()
    note_raw_content_from_params = Map.get(params, "note_raw_content", "")

    note_title =
      if note_title_from_params != "",
        do: note_title_from_params,
        else: (socket.assigns.note_title || "") |> String.trim()

    note_raw_content =
      if note_raw_content_from_params != "",
        do: note_raw_content_from_params,
        else: socket.assigns.note_raw_content || ""

    note_category =
      Formatting.normalize_note_type(
        Map.get(params, "note_category", socket.assigns.note_category)
      )

    cond do
      is_nil(selected_folder_id) ->
        {:noreply, assign(socket, error: "Select or create a project folder first.", info: nil)}

      note_title == "" ->
        {:noreply,
         assign(socket,
           note_title: socket.assigns.note_title,
           note_raw_content: socket.assigns.note_raw_content,
           note_category: note_category,
           vault_item_kind: note_category,
           error: "Note title is required.",
           info: nil
         )}

      String.trim(note_raw_content) == "" ->
        {:noreply,
         assign(socket,
           note_title: note_title,
           note_raw_content: socket.assigns.note_raw_content,
           note_category: note_category,
           vault_item_kind: note_category,
           error: "Note content is required.",
           info: nil
         )}

      true ->
        parsed_entries =
          if Formatting.env_note_type?(note_category) do
            Formatting.parse_env_entries(note_raw_content)
          else
            []
          end

        pending_attrs = %{
          title: note_title,
          note_type: note_category,
          project_folder_id: selected_folder_id,
          raw_content: note_raw_content,
          parsed_entries: parsed_entries,
          entries: parsed_entries
        }

        if socket.assigns.global_passkey_unlocked and
             is_binary(socket.assigns.vault_password) and
             String.trim(socket.assigns.vault_password) != "" do
          socket =
            assign(socket,
              note_category: note_category,
              vault_item_kind: note_category,
              error: nil,
              info: nil
            )

          persist_note(socket, pending_attrs, socket.assigns.vault_password)
        else
          {:noreply,
           assign(socket,
             note_category: note_category,
             vault_item_kind: note_category,
             note_title: note_title,
             note_raw_content: note_raw_content,
             pending_note_attrs: pending_attrs,
             show_global_passkey_modal: true,
             global_passkey_input: "",
             global_passkey_purpose: "save",
             error: nil,
             info: nil
           )}
        end
    end
  end

  def cancel_save_modal(_params, socket) do
    {:noreply,
     assign(socket, show_save_modal: false, note_save_password: "", pending_note_attrs: nil)}
  end

  def cancel_unlock_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_unlock_modal: false,
       unlock_password: "",
       pending_unlock_note_id: nil,
       pending_unlock_note_title: "",
       decrypt_failed_wrong_key: false
     )}
  end

  def unlock_note_with_global_passkey(_params, socket) do
    {:noreply,
     assign(socket,
       show_unlock_modal: false,
       unlock_password: "",
       show_global_passkey_modal: true,
       global_passkey_input: "",
       global_passkey_purpose: "unlock",
       error: nil,
       info: nil
     )}
  end

  def show_per_note_unlock_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_unlock_modal: true,
       unlock_password: "",
       decrypt_failed_wrong_key: false,
       error: nil
     )}
  end

  def confirm_unlock_note(%{"unlock_password" => password}, socket) do
    note_id = socket.assigns.pending_unlock_note_id

    cond do
      is_nil(note_id) ->
        {:noreply,
         assign(socket,
           show_unlock_modal: false,
           unlock_password: "",
           pending_unlock_note_id: nil,
           pending_unlock_note_title: "",
           error: "No note selected to unlock.",
           info: nil
         )}

      password == "" ->
        {:noreply, assign(socket, error: "Password is required to unlock the note.", info: nil)}

      true ->
        note = ProjectVault.get_note!(note_id)

        case VaultKey.decrypt_note_content(note, password) do
          {:ok, raw_content} ->
            {:noreply,
             assign(socket,
               selected_note_id: note.id,
               note_unlocked: true,
               note_category: Formatting.normalize_note_type(note.note_type),
               vault_item_kind: Formatting.normalize_note_type(note.note_type),
               note_title: note.title,
               note_raw_content: raw_content,
               vault_password: password,
               pending_unlock_note_id: nil,
               pending_unlock_note_title: "",
               decrypt_failed_wrong_key: false,
               copy_all_copied: false,
               env_var_value_copied: %{},
               env_var_all_copied: %{},
               show_unlock_modal: false,
               unlock_password: "",
               error: nil,
               info: nil,
               new_note_form_highlight: false
             )}

          {:error, _} ->
            {:noreply,
             assign(socket, error: "Unable to decrypt note with this password.", info: nil)}
        end
    end
  end

  def confirm_save_note(%{"note_save_password" => password}, socket) do
    attrs = socket.assigns.pending_note_attrs

    cond do
      is_nil(attrs) ->
        {:noreply,
         assign(socket,
           show_save_modal: false,
           note_save_password: "",
           error: "Nothing to save.",
           info: nil
         )}

      password == "" ->
        {:noreply, assign(socket, error: "Vault password is required.", info: nil)}

      true ->
        persist_note(socket, attrs, password)
    end
  end

  def show_delete_modal(_params, socket) do
    note_id = socket.assigns.selected_note_id

    if is_nil(note_id) do
      {:noreply, assign(socket, error: "Select a note to delete.", info: nil)}
    else
      {:noreply,
       assign(socket,
         show_delete_modal: true,
         delete_modal_target: :note,
         pending_delete_note_id: note_id,
         pending_delete_note_title: socket.assigns.note_title,
         error: nil,
         info: nil
       )}
    end
  end

  def cancel_delete_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_delete_modal: false,
       delete_modal_target: :note,
       pending_delete_note_id: nil,
       pending_delete_note_title: ""
     )}
  end

  def confirm_delete_note(_params, socket) do
    if socket.assigns[:delete_modal_target] == :vault_item do
      VaultItemEvents.confirm_delete_vault_item(%{}, socket)
    else
      confirm_delete_note_impl(socket)
    end
  end

  defp confirm_delete_note_impl(socket) do
    note_id = socket.assigns.pending_delete_note_id

    if is_nil(note_id) do
      {:noreply,
       assign(socket,
         show_delete_modal: false,
         delete_modal_target: :note,
         pending_delete_note_id: nil,
         pending_delete_note_title: "",
         error: "No note selected to delete.",
         info: nil
       )}
    else
      note = ProjectVault.get_note!(note_id)

      case ProjectVault.delete_note(note) do
        {:ok, _deleted_note} ->
          notes = ProjectVault.list_notes_by_folder(socket.assigns.selected_folder_id)

          {:noreply,
           assign(socket,
             notes: notes,
             selected_note_id: nil,
             note_unlocked: false,
             note_category: "generic_note",
             vault_item_kind: "generic_note",
             note_title: "",
             note_raw_content: "",
             display_mode: :input,
             copy_all_copied: false,
             env_var_value_copied: %{},
             env_var_all_copied: %{},
             show_delete_modal: false,
             delete_modal_target: :note,
             pending_delete_note_id: nil,
             pending_delete_note_title: "",
             info: "Note deleted.",
             error: nil,
             new_note_form_highlight: false
           )}

        {:error, reason} ->
          {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
      end
    end
  end

  def copy_to_clipboard(_params, socket), do: {:noreply, socket}

  def copy_all_env_vars(_params, socket) do
    Process.send_after(self(), :reset_copy_all_copied, 3000)
    {:noreply, assign(socket, copy_all_copied: true)}
  end

  def copy_env_var_value(%{"line_number" => line_number}, socket) do
    line_number_key = to_string(line_number)
    Process.send_after(self(), {:reset_env_var_copied, :value, line_number_key}, 3000)

    {:noreply,
     assign(socket,
       env_var_value_copied: Map.put(socket.assigns.env_var_value_copied, line_number_key, true)
     )}
  end

  def copy_env_var_all(%{"line_number" => line_number}, socket) do
    line_number_key = to_string(line_number)
    Process.send_after(self(), {:reset_env_var_copied, :all, line_number_key}, 3000)

    {:noreply,
     assign(socket,
       env_var_all_copied: Map.put(socket.assigns.env_var_all_copied, line_number_key, true)
     )}
  end

  def persist_note(socket, attrs, password) do
    secure_with_password = is_binary(password) and String.trim(password) != ""

    if !secure_with_password do
      {:noreply, assign(socket, error: "A password or Global Passkey is required.", info: nil)}
    else
      result =
        if socket.assigns.selected_note_id do
          note = ProjectVault.get_note!(socket.assigns.selected_note_id)
          ProjectVault.update_secure_note(note, attrs, password)
        else
          ProjectVault.create_secure_note(attrs, password)
        end

      case result do
        {:ok, note} ->
          notes = ProjectVault.list_notes_by_folder(socket.assigns.selected_folder_id)

          nt = Formatting.normalize_note_type(Map.get(attrs, :note_type, "generic_note"))

          socket =
            assign(socket,
              notes: notes,
              selected_note_id: note.id,
              note_unlocked: true,
              note_category: nt,
              vault_item_kind: nt,
              note_title: Map.get(attrs, :title, ""),
              note_raw_content: Map.get(attrs, :raw_content, ""),
              display_mode: :input,
              copy_all_copied: false,
              env_var_value_copied: %{},
              env_var_all_copied: %{},
              vault_password: password,
              show_save_modal: false,
              note_save_password: "",
              pending_note_attrs: nil,
              info: "Note saved locally.",
              error: nil,
              show_new_note_modal: false,
              new_note_form_highlight: false,
              new_note_tags: ""
            )

          socket =
            if socket.assigns.security_mode == "global_passkey" do
              push_event(socket, "store_vault_key", %{
                key_id: VaultKey.vault_key_id(),
                wrapped_key: password
              })
            else
              socket
            end

          {:noreply, socket}

        {:error, changeset_or_reason} ->
          {:noreply,
           assign(socket, error: ProjectVault.format_error(changeset_or_reason), info: nil)}
      end
    end
  end
end
