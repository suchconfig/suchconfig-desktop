defmodule SuchConfigDesktopWeb.ProjectVaultLive.ArchiveEvents do
  @moduledoc """
  Event handlers for the `.suchvault` archive export and the preview-based
  import flow. Import follows three stages:

    1. User uploads an archive + clicks Import → we open the password modal
       (`import_stage: :password`).
    2. User submits the password → we call `ProjectVault.preview_archive/2`
       and, on success, move to `:preview` showing per-folder routing.
    3. User submits routing → we call `ProjectVault.import_with_routing/4`
       and show a summary flash.
  """

  import Phoenix.Component, only: [assign: 2, upload_errors: 2]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, cancel_upload: 3, push_event: 3]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.Archive.Preview

  def export(params, socket) do
    password = Map.get(params, "archive_password", socket.assigns.archive_password)

    cond do
      is_nil(socket.assigns.selected_folder_id) ->
        {:noreply, assign(socket, error: "Select a folder to export.", info: nil)}

      password == "" ->
        {:noreply, assign(socket, error: "Archive password is required for export.", info: nil)}

      true ->
        folder_id = socket.assigns.selected_folder_id
        dest_dir = socket.assigns[:archive_export_destination_path]

        case ProjectVault.export_secure_archive([folder_id], password) do
          {:ok, archive_binary} ->
            filename = build_export_filename(socket, folder_id)
            encoded = Base.encode64(archive_binary)

            socket =
              socket
              |> assign(archive_password: password, info: "Secure archive generated.", error: nil)

            socket =
              if is_binary(dest_dir) and String.trim(dest_dir) != "" do
                full_path = Path.join(dest_dir, filename)

                push_event(socket, "save_archive_export", %{
                  full_path: full_path,
                  content_base64: encoded
                })
              else
                push_event(socket, "download", %{
                  filename: filename,
                  content: encoded,
                  mime_type: "application/octet-stream",
                  encoding: "base64"
                })
              end

            {:noreply, socket}

          {:error, reason} ->
            {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
        end
    end
  end

  def set_import_options(%{"conflict_strategy" => conflict_strategy}, socket) do
    {:noreply, assign(socket, conflict_strategy: conflict_strategy)}
  end

  def set_import_options(_params, socket) do
    {:noreply, socket}
  end

  def prepare_import(_params, socket) do
    upload = socket.assigns.uploads.archive_file

    cond do
      upload.entries == [] ->
        {:noreply, assign(socket, error: "Select an archive file to import.", info: nil)}

      not Enum.any?(upload.entries, & &1.done?) ->
        {:noreply,
         assign(socket,
           error: "Wait for the file to finish uploading, then click Import Archive again.",
           info: nil
         )}

      (errors =
         upload.entries
         |> Enum.flat_map(fn entry -> upload_errors(upload, entry) end)) != [] ->
        {:noreply,
         assign(socket,
           error: errors |> Enum.map(&format_upload_error/1) |> Enum.uniq() |> Enum.join(" "),
           info: nil
         )}

      true ->
        {:noreply,
         assign(socket,
           import_stage: :password,
           import_preview: nil,
           import_routing: %{},
           archive_password: "",
           info: nil,
           error: nil
         )}
    end
  end

  def cancel_import(_params, socket) do
    {:noreply, reset_archive_import_state(socket)}
  end

  def open_archive_export(_params, socket) do
    socket = reset_archive_import_state(socket)
    {:noreply, assign(socket, archive_panel_mode: :export, archive_export_destination_path: nil)}
  end

  def open_archive_import(_params, socket) do
    socket = reset_archive_import_state(socket)
    {:noreply, assign(socket, archive_panel_mode: :import, archive_password: "")}
  end

  def close_archive_panel(_params, socket) do
    socket = reset_archive_import_state(socket)
    {:noreply, assign(socket, archive_panel_mode: :hidden)}
  end

  defp reset_archive_import_state(socket) do
    socket =
      Enum.reduce(socket.assigns.uploads.archive_file.entries, socket, fn entry, acc ->
        cancel_upload(acc, :archive_file, entry.ref)
      end)

    assign(socket,
      import_stage: :idle,
      import_preview: nil,
      import_routing: %{},
      archive_binary: nil,
      archive_password: "",
      archive_export_destination_path: nil,
      error: nil
    )
  end

  @doc """
  Called from the password modal. Reads the uploaded archive, stashes the
  bytes on the socket, calls `preview_archive/2`, and advances to the
  preview stage on success.
  """
  def preview_archive(%{"archive_password" => password}, socket) do
    if password == "" do
      {:noreply, assign(socket, error: "Archive password is required.", info: nil)}
    else
      uploaded =
        consume_uploaded_entries(socket, :archive_file, fn %{path: path}, _entry ->
          {:ok, File.read!(path)}
        end)

      case uploaded do
        [archive_binary | _] ->
          case ProjectVault.preview_archive(archive_binary, password) do
            {:ok, %Preview{} = preview} ->
              routing = default_routing(preview)

              {:noreply,
               assign(socket,
                 archive_binary: archive_binary,
                 archive_password: password,
                 import_preview: preview,
                 import_routing: routing,
                 import_stage: :preview,
                 info: nil,
                 error: nil
               )}

            {:error, reason} ->
              {:noreply,
               assign(socket,
                 import_stage: :password,
                 error: decode_preview_error(reason),
                 info: nil
               )}
          end

        _ ->
          {:noreply,
           assign(socket,
             import_stage: :idle,
             error: "Select an archive file to import.",
             info: nil
           )}
      end
    end
  end

  @doc """
  Update the per-folder routing decision from the preview modal `<select>`.
  Params shape: `%{"index" => "0", "decision" => "create_new"}` or
  `%{"index" => "1", "decision" => "merge:42"}`.
  """
  def set_routing(%{"index" => index, "decision" => decision}, socket) do
    index = to_int(index)
    current = socket.assigns.import_routing || %{}

    parsed =
      case decision do
        "create_new" -> :create_new
        "skip" -> :skip
        "merge:" <> rest -> {:merge_into, to_int(rest)}
        _ -> :create_new
      end

    routing = Map.put(current, index, parsed)
    {:noreply, assign(socket, import_routing: routing)}
  end

  def set_routing(_params, socket), do: {:noreply, socket}

  def set_routing_name(%{"index" => index, "name" => name}, socket) do
    index = to_int(index)
    current = socket.assigns.import_routing || %{}

    decision =
      case Map.get(current, index, :create_new) do
        :create_new -> {:create_new, name}
        {:create_new, _} -> {:create_new, name}
        other -> other
      end

    {:noreply, assign(socket, import_routing: Map.put(current, index, decision))}
  end

  def set_routing_name(_params, socket), do: {:noreply, socket}

  def confirm_import(%{"conflict_strategy" => conflict_strategy}, socket) do
    archive_binary = socket.assigns.archive_binary
    password = socket.assigns.archive_password
    routing = socket.assigns.import_routing || %{}

    cond do
      not is_binary(archive_binary) or archive_binary == "" ->
        {:noreply,
         assign(socket,
           import_stage: :idle,
           error: "No archive loaded. Please select and decrypt again.",
           info: nil
         )}

      password == "" ->
        {:noreply, assign(socket, error: "Archive password is required.", info: nil)}

      true ->
        vault_pw = socket.assigns.vault_password

        opts =
          if is_binary(vault_pw) and String.trim(vault_pw) != "",
            do: [vault_password: vault_pw],
            else: []

        case ProjectVault.import_with_routing(
               archive_binary,
               password,
               routing,
               conflict_strategy,
               opts
             ) do
          {:ok, summary} ->
            folders = ProjectVault.list_project_folders()
            selected_folder = List.first(folders)
            fid = selected_folder && selected_folder.id

            vault_items =
              if fid && socket.assigns[:vault_item_ui_enabled?],
                do: ProjectVault.list_vault_items_by_folder(fid),
                else: socket.assigns[:vault_items] || []

            {:noreply,
             assign(socket,
               folders: folders,
               selected_folder_id: fid,
               notes: (fid && ProjectVault.list_notes_by_folder(fid)) || [],
               vault_items: vault_items,
               folder_sidebar_expanded: selected_folder != nil,
               selected_note_id: nil,
               selected_vault_item_id: nil,
               editor_focus: :note,
               note_unlocked: false,
               note_category: "generic_note",
               vault_item_kind: "generic_note",
               note_title: "",
               note_raw_content: "",
               import_stage: :idle,
               import_preview: nil,
               import_routing: %{},
               archive_binary: nil,
               archive_password: "",
               conflict_strategy: conflict_strategy,
               archive_panel_mode: :hidden,
               archive_export_destination_path: nil,
               info: format_import_summary(summary),
               error: nil,
               new_note_form_highlight: false
             )}

          {:error, reason} ->
            {:noreply, assign(socket, error: ProjectVault.format_error(reason), info: nil)}
        end
    end
  end

  def confirm_import(params, socket) do
    params = Map.put_new(params, "conflict_strategy", socket.assigns.conflict_strategy)
    confirm_import(params, socket)
  end

  defp default_routing(%Preview{folders: folders}) do
    folders
    |> Enum.map(fn folder -> {folder.index, :create_new} end)
    |> Map.new()
  end

  defp to_int(value) when is_integer(value), do: value

  defp to_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp decode_preview_error(:invalid_password_or_archive),
    do: "Unable to decrypt archive: invalid password or corrupt file."

  defp decode_preview_error(other), do: ProjectVault.format_error(other)

  defp format_import_summary(
         %{
           created: created,
           merged: merged,
           skipped: skipped,
           notes_imported: notes
         } = summary
       ) do
    vi = Map.get(summary, :vault_items_imported, 0)
    vm = Map.get(summary, :vault_items_merged, 0)

    parts =
      [
        if(created > 0, do: "#{created} new project#{maybe_s(created)}", else: nil),
        if(merged > 0, do: "merged into #{merged}", else: nil),
        if(skipped > 0, do: "skipped #{skipped}", else: nil)
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join(", ")

    routing_text = if parts == "", do: "nothing", else: parts

    vault_part =
      cond do
        vi > 0 and vm > 0 ->
          " · #{vi} vault item#{maybe_s(vi)} (#{vm} CRDT-merged)"

        vi > 0 ->
          " · #{vi} vault item#{maybe_s(vi)}"

        vm > 0 ->
          " · #{vm} vault item#{maybe_s(vm)} CRDT-merged"

        true ->
          ""
      end

    "Imported: #{routing_text} · #{notes} note#{maybe_s(notes)}#{vault_part}."
  end

  defp format_import_summary(_), do: "Archive imported successfully."

  defp maybe_s(1), do: ""
  defp maybe_s(_), do: "s"

  defp format_upload_error(:too_large),
    do: "That file is too large (max 50 MB)."

  defp format_upload_error(:too_many_files),
    do: "Only one archive file can be selected at a time."

  defp format_upload_error(:not_accepted),
    do:
      "Invalid file type. Use a .suchvault or .suchconfig secure archive exported from Project Vault."

  defp format_upload_error(error), do: "Upload error: #{inspect(error)}"

  defp build_export_filename(socket, folder_id) do
    folder = Enum.find(socket.assigns.folders, fn f -> f.id == folder_id end)
    base = (folder && sanitize_name(folder.name)) || "suchvault-folder-#{folder_id}"
    "suchvault-#{base}-#{Date.utc_today() |> Date.to_iso8601(:basic)}.suchvault"
  end

  defp sanitize_name(name) when is_binary(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9-]+/, "-")
    |> String.trim("-")
    |> then(fn s -> if s == "", do: "vault", else: s end)
  end

  defp sanitize_name(_), do: "vault"
end
