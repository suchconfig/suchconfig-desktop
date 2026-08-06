defmodule SuchConfigDesktopWeb.ProjectVaultLive.VaultItemEvents do
  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.AiIgnoreTemplates
  alias SuchConfigDesktop.ProjectVault.AiToolingPresence
  alias SuchConfigDesktop.ProjectVault.AutoDetect
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktopWeb.ProjectVaultLive.BrokerItemEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.FolderEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.Formatting
  alias SuchConfigDesktopWeb.ProjectVaultLive.LinkedSyncEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultKey
  alias SuchConfigDesktopWeb.TrustedFolderEvents
  alias SuchConfigDesktopWeb.P2pLanSyncEvents

  def new_vault_item_draft(params, socket) do
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

    {:noreply,
     socket
     |> VaultItemTagEvents.load_draft_tags()
     |> assign(
       new_note_draft_assigns(
         editor_focus: :vault_item,
         note_unlocked: true
       )
     )}
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
        note_title: "",
        note_raw_content: "",
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

  def new_vault_item(_params, socket) do
    if not socket.assigns.vault_item_ui_enabled? do
      {:noreply,
       assign(socket, error: "CRDT vault items are not available on this build.", info: nil)}
    else
      socket = VaultKey.ensure_vault_key_from_registry(socket)
      folder_id = socket.assigns.selected_folder_id
      pw = socket.assigns.vault_password

      cond do
        is_nil(folder_id) ->
          {:noreply, assign(socket, error: "Select or create a project folder first.", info: nil)}

        not (is_binary(pw) and String.trim(pw) != "") ->
          {:noreply,
           assign(socket,
             show_global_passkey_modal: true,
             global_passkey_purpose: "save",
             pending_unlock_action: :new_vault_item,
             error: nil,
             info: nil
           )}

        true ->
          n = System.unique_integer([:positive])

          attrs = %{
            title: "Vault item #{n}",
            kind: "generic_note",
            security_mode: "global_passkey",
            project_folder_id: folder_id,
            body: ""
          }

          case ProjectVault.save_vault_item(attrs, pw) do
            {:ok, item} ->
              items = ProjectVault.list_vault_items_by_folder(folder_id)

              {:noreply,
               assign(socket,
                 vault_items: items,
                 selected_note_id: nil,
                 selected_vault_item_id: item.id,
                 editor_focus: :vault_item,
                 note_title: item.title,
                 note_raw_content: "",
                 note_category: item.kind,
                 note_unlocked: true,
                 info: "Vault item created.",
                 error: nil,
                 new_note_form_highlight: false
               )}

            {:error, reason} ->
              {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
          end
      end
    end
  end

  def select_vault_item(%{"id" => id}, socket) do
    if not socket.assigns.vault_item_ui_enabled? do
      {:noreply, socket}
    else
      socket = VaultKey.ensure_vault_key_from_registry(socket)
      item_id = String.to_integer(id)
      item = ProjectVault.get_vault_item!(item_id)
      pw = socket.assigns.vault_password

      case ProjectVault.decrypt_vault_item_body(item, pw) do
        {:ok, body} ->
          {:noreply,
           socket
           |> assign(
             selected_vault_item_id: item.id,
             selected_note_id: nil,
             note_unlocked: true,
             editor_focus: :vault_item,
             note_title: item.title,
             note_raw_content: body,
             note_category: item.kind,
             error: nil,
             info: nil,
             new_note_form_highlight: false
           )
           |> VaultItemTagEvents.load_item_tags(item, pw)
           |> assign_vault_history_count(item, pw)
           |> BrokerItemEvents.assign_broker_item_state(item, pw)
           |> LinkedSyncEvents.assign_sync_status(auto_open_review?: true)}

        {:error, _} ->
          {:noreply,
           assign(socket,
             error: "Could not decrypt this vault item with the current vault key.",
             info: nil
           )}
      end
    end
  end

  def save_vault_item_document(params, socket) do
    if not socket.assigns.vault_item_ui_enabled? do
      {:noreply, socket}
    else
      id = socket.assigns.selected_vault_item_id

      draft? =
        is_nil(id) &&
          (socket.assigns[:show_new_note_modal] || socket.assigns[:new_note_form_highlight])

      cond do
        is_nil(id) && not draft? ->
          {:noreply, assign(socket, error: "Select a vault item to save.", info: nil)}

        true ->
          socket = VaultKey.ensure_vault_key_from_registry(socket)
          pw = socket.assigns.vault_password
          title = Map.get(params, "note_title", socket.assigns.note_title) |> String.trim()
          body = Map.get(params, "note_raw_content", socket.assigns.note_raw_content)

          tags =
            if socket.assigns[:show_new_note_modal] do
              parse_modal_tags(params, socket)
            else
              socket.assigns[:item_tags] || []
            end

          kind =
            cond do
              Formatting.project_details_vault_title?(title) -> "guideline"
              true -> VaultItemTags.kind_from_tags(tags, "generic_note")
            end

          cond do
            title == "" ->
              {:noreply, assign(socket, error: "Title is required.", info: nil)}

            not (is_binary(pw) and String.trim(pw) != "") ->
              {:noreply,
               assign(socket,
                 show_global_passkey_modal: true,
                 global_passkey_purpose: "save",
                 pending_unlock_action: :save_vault_item,
                 error: nil,
                 info: nil
               )}

            true ->
              attrs = %{
                id: id,
                title: title,
                kind: kind,
                security_mode: "global_passkey",
                project_folder_id: socket.assigns.selected_folder_id,
                body: body || "",
                frontmatter: VaultItemTagEvents.frontmatter_for_save(socket, id, tags)
              }

              case ProjectVault.save_vault_item(attrs, pw) do
                {:ok, item} ->
                  items =
                    ProjectVault.list_vault_items_by_folder(socket.assigns.selected_folder_id)

                  {:noreply,
                   socket
                   |> assign(
                     vault_items: items,
                     selected_vault_item_id: item.id,
                     note_title: item.title,
                     note_raw_content: body || "",
                     note_category: item.kind,
                     info: "Vault item saved.",
                     error: nil,
                     show_new_note_modal: false,
                     new_note_form_highlight: false,
                     new_note_tags: ""
                   )
                   |> VaultItemTagEvents.load_item_tags(item, pw)
                   |> VaultItemTagEvents.assign_folder_tags()
                   |> LinkedSyncEvents.assign_sync_status()
                   |> LinkedSyncEvents.maybe_auto_push_after_save()
                   |> tap(fn s ->
                     TrustedFolderEvents.broadcast_sync(s.assigns[:vault_session_id], "projects")
                     P2pLanSyncEvents.broadcast_sync(s.assigns[:vault_session_id], "projects")
                   end)}

                {:error, reason} ->
                  {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
              end
          end
      end
    end
  end

  def show_delete_vault_item_modal(_params, socket) do
    id = socket.assigns.selected_vault_item_id

    if is_nil(id) do
      {:noreply, assign(socket, error: "Select a vault item to delete.", info: nil)}
    else
      {:noreply,
       assign(socket,
         show_delete_modal: true,
         delete_modal_target: :vault_item,
         pending_delete_note_title: socket.assigns.note_title,
         error: nil,
         info: nil
       )}
    end
  end

  def confirm_delete_vault_item(_params, socket) do
    id = socket.assigns.selected_vault_item_id

    cond do
      is_nil(id) ->
        {:noreply,
         assign(socket,
           show_delete_modal: false,
           delete_modal_target: :note,
           error: "No vault item selected.",
           info: nil
         )}

      true ->
        case ProjectVault.delete_vault_item(id) do
          {:ok, _} ->
            items = ProjectVault.list_vault_items_by_folder(socket.assigns.selected_folder_id)

            socket =
              case socket.assigns[:vault_session_id] do
                session_id when is_binary(session_id) ->
                  TrustedFolderEvents.broadcast_sync(session_id, "projects")
                  P2pLanSyncEvents.broadcast_sync(session_id, "projects")
                  socket

                _ ->
                  socket
              end

            {:noreply,
             assign(socket,
               vault_items: items,
               selected_vault_item_id: nil,
               editor_focus: :note,
               note_title: "",
               note_raw_content: "",
               note_category: "generic_note",
               show_delete_modal: false,
               delete_modal_target: :note,
               info: "Vault item deleted.",
               error: nil,
               new_note_form_highlight: false
             )}

          {:error, reason} ->
            {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
        end
    end
  end

  def apply_link_project_scan(socket, {:ok, project_data}) do
    candidates = Map.get(project_data, :vault_file_candidates, []) || []
    selection = vault_candidate_selection(candidates)
    scan_path = Map.get(project_data, :path)
    project_name = Map.get(project_data, :project_name)
    ai_tooling = Map.get(project_data, :ai_tooling) || AiToolingPresence.analyze(scan_path || "")
    scaffold_selected = AiToolingPresence.scaffold_selection(ai_tooling)
    body = generate_link_project_details_markdown(project_data)

    if is_binary(body) and String.trim(body) != "" do
      assign(socket,
        link_project_stage: :preview,
        link_project_preview: body,
        link_project_project_data: project_data,
        link_project_scan_path: scan_path,
        link_project_project_name: project_name,
        link_project_vault_candidates: candidates,
        link_project_vault_selected: selection,
        link_project_ai_tooling: ai_tooling,
        link_project_scaffold_selected: scaffold_selected,
        link_project_existing_notes_strategy: nil,
        link_project_error: nil,
        info: "Scan complete. Review the preview and click Confirm to import.",
        error: nil
      )
    else
      assign(socket,
        link_project_stage: :select_path,
        link_project_scan_path: nil,
        link_project_ai_tooling: nil,
        link_project_scaffold_selected: %{},
        link_project_error: "Scan finished but no Project Details content was generated.",
        info: nil,
        error: nil
      )
    end
  end

  def apply_link_project_scan(socket, {:error, reason}) do
    assign(socket,
      link_project_stage: :select_path,
      link_project_scan_path: nil,
      link_project_ai_tooling: nil,
      link_project_scaffold_selected: %{},
      link_project_error: to_string(reason),
      info: nil,
      error: nil
    )
  end

  def open_link_project_modal(_params, socket) do
    if is_nil(socket.assigns.selected_folder_id) do
      {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}
    else
      {:noreply,
       assign(socket,
         show_link_project_modal: true,
         link_project_stage: :select_path,
         link_project_preview: nil,
         link_project_project_data: nil,
         link_project_scan_path: nil,
         link_project_project_name: nil,
         link_project_vault_candidates: [],
         link_project_vault_selected: %{},
         link_project_ai_tooling: nil,
         link_project_scaffold_selected: %{},
         link_project_existing_notes_strategy: nil,
         link_project_error: nil,
         link_project_run_sentinel: false,
         error: nil,
         info: nil
       )}
    end
  end

  def open_link_project_modal_for_path(path, socket, opts \\ [])

  def open_link_project_modal_for_path(path, socket, opts) when is_binary(path) do
    trimmed = String.trim(path)
    run_sentinel? = Keyword.get(opts, :run_sentinel, false) == true

    cond do
      trimmed == "" ->
        {:noreply, socket}

      is_nil(socket.assigns.selected_folder_id) ->
        {:noreply, assign(socket, error: "Select a project folder first.", info: nil)}

      true ->
        send(self(), {:link_project_scan_disk, trimmed})

        {:noreply,
         assign(socket,
           show_link_project_modal: true,
           link_project_stage: :scanning,
           link_project_preview: nil,
           link_project_project_data: nil,
           link_project_scan_path: trimmed,
           link_project_project_name: nil,
           link_project_vault_candidates: [],
           link_project_vault_selected: %{},
           link_project_ai_tooling: nil,
           link_project_scaffold_selected: %{},
           link_project_existing_notes_strategy: nil,
           link_project_error: nil,
           link_project_run_sentinel: run_sentinel?,
           error: nil,
           info: nil
         )}
    end
  end

  def open_link_project_modal_for_path(_path, socket, _opts), do: {:noreply, socket}

  def cancel_link_project_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_link_project_modal: false,
       link_project_stage: :idle,
       link_project_preview: nil,
       link_project_project_data: nil,
       link_project_scan_path: nil,
       link_project_project_name: nil,
       link_project_vault_candidates: [],
       link_project_vault_selected: %{},
       link_project_ai_tooling: nil,
       link_project_scaffold_selected: %{},
       link_project_existing_notes_strategy: nil,
       link_project_error: nil,
       link_project_run_sentinel: false,
       error: nil,
       info: nil
     )}
  end

  def link_project_sentinel_change(params, socket) do
    {:noreply,
     assign(socket, link_project_run_sentinel: checkbox_checked?(params, "run_sentinel_scan"))}
  end

  def link_project_existing_notes_change(params, socket) do
    strategy =
      params
      |> Map.get("existing_notes", "")
      |> to_string()
      |> String.trim()

    strategy = if strategy in ["overwrite", "duplicate"], do: strategy, else: nil

    {:noreply,
     assign(socket, link_project_existing_notes_strategy: strategy, link_project_error: nil)}
  end

  def link_project_vault_toggle(%{"path" => path}, socket) when is_binary(path) do
    sel = socket.assigns[:link_project_vault_selected] || %{}
    cur = Map.get(sel, path, true)
    {:noreply, assign(socket, link_project_vault_selected: Map.put(sel, path, not cur))}
  end

  def link_project_vault_toggle(_params, socket), do: {:noreply, socket}

  def link_project_scaffold_toggle(%{"path" => path}, socket) when is_binary(path) do
    sel = socket.assigns[:link_project_scaffold_selected] || %{}
    cur = Map.get(sel, path, false)
    {:noreply, assign(socket, link_project_scaffold_selected: Map.put(sel, path, not cur))}
  end

  def link_project_scaffold_toggle(_params, socket), do: {:noreply, socket}

  def folder_select_error(%{"error" => message}, socket) when is_binary(message) do
    if socket.assigns[:show_link_project_modal] do
      {:noreply,
       assign(socket,
         link_project_stage: :select_path,
         link_project_scan_path: nil,
         link_project_error: message,
         error: nil,
         info: nil
       )}
    else
      {:noreply, assign(socket, error: message, info: nil)}
    end
  end

  def folder_select_error(_params, socket), do: {:noreply, socket}

  defp vault_candidate_selection(candidates) do
    Map.new(candidates, fn c ->
      rel = Map.get(c, :relative_path) || Map.get(c, "relative_path")
      {rel, true}
    end)
  end

  defp generate_link_project_details_markdown(project_data) do
    case safe_generate_setup_guide(project_data) do
      {:ok, body} when is_binary(body) ->
        if String.trim(body) != "",
          do: body,
          else: fallback_link_project_details_markdown(project_data)

      _ ->
        fallback_link_project_details_markdown(project_data)
    end
  end

  defp safe_generate_setup_guide(project_data) do
    case AutoDetect.generate_plan(project_data, format: :setup_guide) do
      {:ok, plan} ->
        body = plan[:markdown] || plan["markdown"] || inspect_plan(plan)
        {:ok, body}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception -> {:error, Exception.message(exception)}
  end

  defp fallback_link_project_details_markdown(project_data) do
    name = Map.get(project_data, :project_name) || "Project"
    path = Map.get(project_data, :path) || ""
    candidates = Map.get(project_data, :vault_file_candidates, []) || []

    files_section =
      candidates
      |> Enum.map(fn c -> Map.get(c, :relative_path) || Map.get(c, "relative_path") end)
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&"- `#{&1}`")
      |> Enum.join("\n")

    files_block =
      if files_section == "" do
        "_No root config files detected._"
      else
        files_section
      end

    """
    # #{name}

    > Auto-generated by SuchConfig Project Vault
    > Linked from `#{path}`

    ## Overview

    #{name} was linked from your local filesystem. Confirm import to add config files as secure notes in this vault folder.

    ## Detected config files

    #{files_block}
    """
  end

  defp link_project_folder_has_items?(socket) do
    notes = socket.assigns[:notes] || []
    vault_items = socket.assigns[:vault_items] || []
    Formatting.folder_item_count(notes, vault_items) > 0
  end

  defp link_project_import_strategy(socket) do
    case socket.assigns[:link_project_existing_notes_strategy] do
      strategy when strategy in ["overwrite", "duplicate"] -> strategy
      _ -> if link_project_folder_has_items?(socket), do: nil, else: "duplicate"
    end
  end

  defp import_link_project_selected_config_notes(socket, folder_id, pw) do
    root = socket.assigns[:link_project_scan_path]
    candidates = socket.assigns[:link_project_vault_candidates] || []
    sel = socket.assigns[:link_project_vault_selected] || %{}
    strategy = link_project_import_strategy(socket)

    if not is_binary(root) or String.trim(root) == "" or
         strategy not in ["overwrite", "duplicate"] do
      {0, 0}
    else
      chosen =
        Enum.filter(candidates, fn c ->
          rel = Map.get(c, :relative_path) || Map.get(c, "relative_path")
          Map.get(sel, rel, true)
        end)

      exp_root = root |> Path.expand() |> String.trim_trailing("/")

      folder_items = ProjectVault.list_vault_items_by_folder(folder_id)
      items_by_title = Map.new(folder_items, &{&1.title, &1})
      used_titles = folder_items |> MapSet.new(& &1.title)

      {imported, skipped, _used} =
        Enum.reduce(chosen, {0, 0, used_titles}, fn c, {ok, skip, used} ->
          abs = Map.get(c, :absolute_path) || Map.get(c, "absolute_path")
          exp_abs = abs |> Path.expand() |> String.trim_trailing("/")

          if exp_abs != exp_root and not String.starts_with?(exp_abs, exp_root <> "/") do
            {ok, skip + 1, used}
          else
            case File.read(abs) do
              {:ok, bin} when is_binary(bin) ->
                if String.valid?(bin) and byte_size(bin) <= 400_000 do
                  note_type = Map.get(c, :note_type) || "generic_note"
                  nt = Formatting.normalize_note_type(note_type)
                  kind = link_import_vault_kind(nt)

                  rel = Map.get(c, :relative_path) || Map.get(c, "relative_path")

                  base =
                    rel |> String.trim() |> then(fn s -> if s == "", do: "imported", else: s end)

                  mtime =
                    case LinkedFrontmatter.file_mtime_seconds(abs) do
                      {:ok, s} -> s
                      _ -> 0
                    end

                  case persist_link_project_vault_item(
                         strategy,
                         base,
                         rel,
                         bin,
                         kind,
                         folder_id,
                         mtime,
                         pw,
                         items_by_title,
                         used
                       ) do
                    {:ok, title} -> {ok + 1, skip, MapSet.put(used, title)}
                    {:error, _} -> {ok, skip + 1, used}
                  end
                else
                  {ok, skip + 1, used}
                end

              {:error, _} ->
                {ok, skip + 1, used}
            end
          end
        end)

      {imported, skipped}
    end
  end

  defp link_import_vault_kind(note_type) do
    if Formatting.env_note_type?(note_type), do: "env_note", else: "generic_note"
  end

  defp persist_link_project_vault_item(
         "overwrite",
         title,
         rel,
         body,
         kind,
         folder_id,
         mtime,
         pw,
         items_by_title,
         _used
       ) do
    attrs = link_vault_item_attrs(title, rel, body, kind, folder_id, mtime, items_by_title)

    case ProjectVault.save_vault_item(attrs, pw) do
      {:ok, _} -> {:ok, title}
      error -> error
    end
  end

  defp persist_link_project_vault_item(
         "duplicate",
         base,
         rel,
         body,
         kind,
         folder_id,
         mtime,
         pw,
         _items_by_title,
         used
       ) do
    title = next_available_vault_title(used, base)
    attrs = link_vault_item_attrs(title, rel, body, kind, folder_id, mtime, %{})

    case ProjectVault.save_vault_item(attrs, pw) do
      {:ok, _} -> {:ok, title}
      error -> error
    end
  end

  defp link_vault_item_attrs(title, rel, body, kind, folder_id, mtime, items_by_title) do
    import_tags = if kind == "env_note", do: ["Environment"], else: []

    frontmatter =
      rel
      |> LinkedFrontmatter.import_bundle(body, mtime)
      |> VaultItemTags.merge_frontmatter(import_tags)

    base = %{
      title: title,
      kind: kind,
      security_mode: "global_passkey",
      project_folder_id: folder_id,
      body: body,
      frontmatter: frontmatter
    }

    case Map.get(items_by_title, title) do
      nil -> base
      item -> Map.put(base, :id, item.id)
    end
  end

  defp next_available_vault_title(used, base) do
    if MapSet.member?(used, base) do
      Enum.find_value(2..999, fn i ->
        t = "#{base} (#{i})"
        if MapSet.member?(used, t), do: nil, else: t
      end) || "#{base} (import)"
    else
      base
    end
  end

  defp next_vault_project_details_title(folder_id) do
    used =
      folder_id
      |> ProjectVault.list_vault_items_by_folder()
      |> MapSet.new(& &1.title)

    base = "Project Details"

    if MapSet.member?(used, base) do
      Enum.find_value(2..999, fn i ->
        t = "#{base} (#{i})"
        if MapSet.member?(used, t), do: nil, else: t
      end) || "#{base} (import)"
    else
      base
    end
  end

  defp format_link_project_confirm_info(vault_title, imported, skipped, scaffold_stats) do
    base = "Saved \"#{vault_title}\"."

    import_part =
      cond do
        imported > 0 and skipped > 0 ->
          " Imported #{imported} secure note(s); skipped #{skipped} file(s)."

        imported > 0 ->
          " Imported #{imported} vault item(s)."

        skipped > 0 ->
          " Skipped #{skipped} file(s)."

        true ->
          ""
      end

    created = Map.get(scaffold_stats, :created, 0)
    skipped_existing = Map.get(scaffold_stats, :skipped_existing, 0)

    scaffold_part =
      cond do
        created > 0 and skipped_existing > 0 ->
          " Created #{created} AI ignore file(s); skipped #{skipped_existing} existing."

        created > 0 ->
          " Created #{created} AI ignore file(s)."

        skipped_existing > 0 ->
          " Skipped #{skipped_existing} existing AI ignore file(s)."

        true ->
          ""
      end

    base <> import_part <> scaffold_part
  end

  def confirm_link_project(_params, socket) do
    preview = socket.assigns.link_project_preview
    folder_id = socket.assigns.selected_folder_id
    pw = socket.assigns.vault_password
    root = socket.assigns[:link_project_scan_path]

    cond do
      not is_binary(preview) or String.trim(preview) == "" ->
        {:noreply,
         assign(socket,
           link_project_error: "Nothing to save. Scan a project folder first.",
           error: nil,
           info: nil
         )}

      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "Select a folder first.", info: nil)}

      not is_binary(root) or String.trim(root) == "" ->
        {:noreply,
         assign(socket,
           link_project_error: "Scan path missing. Choose a folder again.",
           error: nil,
           info: nil
         )}

      not (is_binary(pw) and String.trim(pw) != "") ->
        {:noreply,
         assign(socket,
           show_global_passkey_modal: true,
           show_link_project_modal: false,
           global_passkey_purpose: "save",
           pending_unlock_action: :confirm_link_project,
           link_project_error: nil,
           error: nil,
           info: nil
         )}

      link_project_folder_has_items?(socket) and
          socket.assigns[:link_project_existing_notes_strategy] not in ["overwrite", "duplicate"] ->
        {:noreply,
         assign(socket,
           link_project_error: "Choose whether to overwrite existing notes or create duplicates.",
           error: nil,
           info: nil
         )}

      true ->
        case write_selected_scaffolds(socket, root) do
          {:error, reason} ->
            {:noreply,
             assign(socket,
               link_project_error:
                 "Failed to write AI ignore file: #{format_scaffold_error(reason)}",
               error: nil,
               info: nil
             )}

          {:ok, scaffold_stats} ->
            tool_tags = folder_tags_after_scaffold(socket, scaffold_stats)
            run_sentinel? = socket.assigns[:link_project_run_sentinel] == true

            with {:ok, _} <- link_folder_project_path(folder_id, root, tool_tags),
                 {:ok, item} <- upsert_project_details_vault_item(folder_id, preview, pw) do
              {imported, skipped} =
                import_link_project_selected_config_notes(socket, folder_id, pw)

              items = ProjectVault.list_vault_items_by_folder(folder_id)
              notes = ProjectVault.list_notes_by_folder(folder_id)
              folders = ProjectVault.list_project_folders()

              info =
                format_link_project_confirm_info(item.title, imported, skipped, scaffold_stats)

              socket =
                socket
                |> assign(
                  folders: folders,
                  vault_items: items,
                  notes: notes,
                  selected_note_id: nil,
                  selected_vault_item_id: item.id,
                  editor_focus: :vault_item,
                  note_title: item.title,
                  note_raw_content: preview,
                  note_category: item.kind,
                  show_link_project_modal: false,
                  link_project_preview: nil,
                  link_project_stage: :idle,
                  link_project_project_data: nil,
                  link_project_scan_path: nil,
                  link_project_project_name: nil,
                  link_project_vault_candidates: [],
                  link_project_vault_selected: %{},
                  link_project_ai_tooling: nil,
                  link_project_scaffold_selected: %{},
                  link_project_existing_notes_strategy: nil,
                  link_project_error: nil,
                  link_project_run_sentinel: false,
                  info: info,
                  error: nil,
                  new_note_form_highlight: false
                )
                |> VaultItemTagEvents.load_item_tags(item, pw)
                |> VaultItemTagEvents.assign_folder_tags()
                |> maybe_start_link_onboard_scan(root, folder_id, run_sentinel?)

              {:noreply, socket}
            else
              {:error, reason} ->
                {:noreply,
                 assign(socket,
                   link_project_error: ProjectVault.format_error(reason),
                   error: nil,
                   info: nil
                 )}
            end
        end
    end
  end

  defp write_selected_scaffolds(socket, root) do
    sel = socket.assigns[:link_project_scaffold_selected] || %{}

    paths =
      sel
      |> Enum.filter(fn {_path, selected?} -> selected? end)
      |> Enum.map(fn {path, _} -> path end)
      |> Enum.sort()

    Enum.reduce_while(
      paths,
      {:ok, %{created: 0, skipped_existing: 0, created_paths: []}},
      fn path, {:ok, acc} ->
        case AiIgnoreTemplates.write_if_missing(root, path) do
          :ok ->
            {:cont,
             {:ok,
              %{
                acc
                | created: acc.created + 1,
                  created_paths: [path | acc.created_paths]
              }}}

          {:skipped, :exists} ->
            {:cont, {:ok, %{acc | skipped_existing: acc.skipped_existing + 1}}}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
  end

  defp folder_tags_after_scaffold(socket, scaffold_stats) do
    ai = socket.assigns[:link_project_ai_tooling] || %{}
    detected = List.wrap(ai[:folder_tags])

    from_writes =
      (scaffold_stats[:created_paths] || [])
      |> Enum.map(&tag_for_scaffold_path/1)
      |> Enum.reject(&is_nil/1)

    (detected ++ from_writes)
    |> Enum.map(&VaultItemTags.normalize_tag/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.uniq()
  end

  defp tag_for_scaffold_path(".cursorignore"), do: "Cursor"
  defp tag_for_scaffold_path(".claudeignore"), do: "Claude"
  defp tag_for_scaffold_path(".windsurfignore"), do: "Windsurf"
  defp tag_for_scaffold_path(".aiderignore"), do: "Aider"
  defp tag_for_scaffold_path(".kiroignore"), do: "Kiro"
  defp tag_for_scaffold_path(_), do: nil

  defp format_scaffold_error(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_scaffold_error(reason), do: inspect(reason)

  defp link_folder_project_path(folder_id, root, tool_tags) do
    folder = ProjectVault.get_project_folder!(folder_id)
    existing_tags = VaultItemTags.decode(folder.tags)
    merged_tags = (existing_tags ++ List.wrap(tool_tags)) |> Enum.uniq()

    attrs = %{
      linked_project_path: root,
      linked_sync_enabled: true,
      tags: VaultItemTags.encode(merged_tags)
    }

    case ProjectVault.update_project_folder(folder, attrs) do
      {:ok, _} -> {:ok, :linked}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_start_link_onboard_scan(socket, root, folder_id, run_sentinel?) do
    if ProjectVault.security_sentinel_license_enabled?() and run_sentinel? do
      SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents.start_onboard_scan(
        socket,
        root,
        folder_id
      )
    else
      socket
    end
  end

  defp checkbox_checked?(params, key) do
    case Map.get(params, key) do
      true -> true
      "true" -> true
      "on" -> true
      _ -> false
    end
  end

  defp upsert_project_details_vault_item(folder_id, preview, pw) do
    existing =
      folder_id
      |> ProjectVault.list_vault_items_by_folder()
      |> Enum.find(&Formatting.project_details_vault_item?(&1.title, &1.kind))

    attrs =
      if existing do
        %{
          id: existing.id,
          title: existing.title,
          kind: "guideline",
          security_mode: "global_passkey",
          project_folder_id: folder_id,
          body: preview
        }
      else
        %{
          title: next_vault_project_details_title(folder_id),
          kind: "guideline",
          security_mode: "global_passkey",
          project_folder_id: folder_id,
          body: preview
        }
      end

    ProjectVault.save_vault_item(attrs, pw)
  end

  defp inspect_plan(%{} = plan) do
    case Map.get(plan, :sections) || Map.get(plan, "sections") do
      list when is_list(list) ->
        list
        |> Enum.map(fn s -> Map.get(s, :body) || Map.get(s, "body") || "" end)
        |> Enum.join("\n\n")

      _ ->
        Jason.encode!(plan)
    end
  end

  defp inspect_plan(_), do: ""

  defp parse_modal_tags(params, socket) do
    Map.get(params, "new_note_tags", socket.assigns[:new_note_tags] || "")
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp assign_vault_history_count(socket, item, pw) do
    count =
      case ProjectVault.vault_item_change_count(item, pw) do
        {:ok, n} -> n
        _ -> 0
      end

    assign(socket, vault_item_change_count: count)
  end
end
