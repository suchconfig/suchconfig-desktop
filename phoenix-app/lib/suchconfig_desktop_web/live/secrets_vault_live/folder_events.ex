defmodule SuchConfigDesktopWeb.SecretsVaultLive.FolderEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.Folder
  alias SuchConfigDesktopWeb.SecretsVaultLive.Formatting
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData

  def folder_toolbar_change(%{"folder_id" => id}, socket) do
    select_folder(%{"id" => id}, socket)
  end

  def select_folder(%{"id" => id}, socket) do
    folder_id = Formatting.parse_folder_select_id(id)

    items =
      if folder_id == Formatting.show_all_folder_id() or is_integer(folder_id) do
        filter_items(socket, folder_id)
      else
        []
      end

    {:noreply,
     socket
     |> assign(
       selected_folder_id: folder_id,
       selected_item_id: nil,
       vault_panel: :stats,
       items: items,
       item_title: "",
       item_kind: "password",
       username: "",
       url: "",
       public_key: "",
       fingerprint: "",
       secret_body: "",
       show_secret: false,
       item_tags: [],
       search_query: "",
       error: nil
     )
     |> ViewData.assign_view_data(load_all_items: Formatting.show_all_folder_selected?(folder_id))}
  end

  def open_new_folder_modal(_params, socket) do
    {:noreply,
     assign(socket, show_new_folder_modal: true, folder_name: "", folder_description: "")}
  end

  def close_new_folder_modal(_params, socket) do
    {:noreply, assign(socket, show_new_folder_modal: false)}
  end

  def create_folder(%{"folder" => params}, socket) do
    attrs = %{name: Map.get(params, "name", ""), description: Map.get(params, "description")}

    case SecretsVault.create_folder(attrs) do
      {:ok, folder} ->
        folders = SecretsVault.list_folders()

        socket =
          cond do
            socket.assigns.show_new_entry_modal ->
              assign(socket,
                folders: folders,
                new_entry_folder_id: folder.id,
                show_new_folder_modal: false,
                info: "Folder created.",
                error: nil
              )

            socket.assigns.selected_item_id ->
              assign(socket,
                folders: folders,
                entry_folder_id: folder.id,
                show_new_folder_modal: false,
                info: "Folder created.",
                error: nil
              )

            true ->
              items = SecretsVault.list_items(folder.id)

              assign(socket,
                folders: folders,
                selected_folder_id: folder.id,
                items: items,
                show_new_folder_modal: false,
                info: "Folder created.",
                error: nil
              )
          end

        {:noreply, socket |> ViewData.assign_view_data(refresh_all_items: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, error: folder_error(changeset))}
    end
  end

  def open_edit_folder(%{"id" => id}, socket) do
    folder = SecretsVault.get_folder!(parse_id(id))

    {:noreply,
     assign(socket,
       show_edit_folder_modal: true,
       editing_folder_id: folder.id,
       edit_folder_name: folder.name,
       edit_folder_description: folder.description || "",
       edit_folder_delete_confirm: false,
       error: nil
     )}
  end

  def close_edit_folder_modal(_params, socket) do
    {:noreply,
     assign(socket,
       show_edit_folder_modal: false,
       editing_folder_id: nil,
       edit_folder_name: "",
       edit_folder_description: "",
       edit_folder_delete_confirm: false
     )}
  end

  def request_delete_folder(_params, socket) do
    if socket.assigns.editing_folder_id do
      {:noreply, assign(socket, edit_folder_delete_confirm: true, error: nil)}
    else
      {:noreply, socket}
    end
  end

  def cancel_delete_folder_confirm(_params, socket) do
    {:noreply, assign(socket, edit_folder_delete_confirm: false)}
  end

  def delete_folder(_params, socket) do
    folder_id = socket.assigns.editing_folder_id

    cond do
      is_nil(folder_id) ->
        {:noreply, assign(socket, error: "No folder selected.")}

      true ->
        folder = SecretsVault.get_folder!(folder_id)

        if folder.name == Folder.unassociated_name() do
          {:noreply,
           assign(socket,
             error: "The Unassociated folder cannot be deleted.",
             edit_folder_delete_confirm: false
           )}
        else
          delete_folder_and_refresh(socket, folder)
        end
    end
  end

  def update_folder(%{"folder" => params}, socket) do
    folder = SecretsVault.get_folder!(socket.assigns.editing_folder_id)

    case SecretsVault.update_folder(folder, %{
           name: Map.get(params, "name", folder.name),
           description: Map.get(params, "description")
         }) do
      {:ok, _} ->
        folders = SecretsVault.list_folders()

        {:noreply,
         socket
         |> assign(
           folders: folders,
           show_edit_folder_modal: false,
           editing_folder_id: nil,
           edit_folder_name: "",
           edit_folder_description: "",
           edit_folder_delete_confirm: false,
           info: "Folder updated.",
           error: nil
         )
         |> ViewData.assign_view_data(refresh_all_items: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, error: folder_error(changeset))}
    end
  end

  defp delete_folder_and_refresh(socket, folder) do
    case SecretsVault.delete_folder(folder) do
      {:ok, _} ->
        folders = SecretsVault.list_folders()
        was_selected = socket.assigns.selected_folder_id == folder.id

        {selected_folder_id, items} =
          cond do
            folders == [] ->
              {nil, []}

            was_selected ->
              next = List.first(folders)
              {next.id, SecretsVault.list_items(next.id)}

            true ->
              fid = socket.assigns.selected_folder_id
              {fid, SecretsVault.list_items(fid)}
          end

        {:noreply,
         socket
         |> assign(
           folders: folders,
           selected_folder_id: selected_folder_id,
           items: items,
           selected_item_id: if(was_selected, do: nil, else: socket.assigns.selected_item_id),
           item_title: if(was_selected, do: "", else: socket.assigns.item_title),
           username: if(was_selected, do: "", else: socket.assigns.username),
           url: if(was_selected, do: "", else: socket.assigns.url),
           public_key: if(was_selected, do: "", else: socket.assigns.public_key),
           fingerprint: if(was_selected, do: "", else: socket.assigns.fingerprint),
           secret_body: if(was_selected, do: "", else: socket.assigns.secret_body),
           show_secret: false,
           show_edit_folder_modal: false,
           editing_folder_id: nil,
           edit_folder_name: "",
           edit_folder_description: "",
           edit_folder_delete_confirm: false,
           info: "Folder deleted.",
           error: nil
         )
         |> ViewData.assign_view_data(refresh_all_items: true)}

      {:error, changeset} ->
        {:noreply,
         assign(socket,
           error: folder_error(changeset),
           edit_folder_delete_confirm: false
         )}
    end
  end

  defp filter_items(socket, folder_id) do
    query = socket.assigns.search_query || ""
    password = socket.assigns.vault_password
    query_folder_id = Formatting.items_query_folder_id(folder_id)

    if socket.assigns.global_passkey_unlocked and password != "" and String.trim(query) != "" do
      SecretsVault.search_items(query_folder_id, query, password)
    else
      SecretsVault.list_items(query_folder_id)
    end
  end

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(id) when is_integer(id), do: id
  defp parse_id(_), do: nil

  defp folder_error(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, _} -> msg end)
    |> Enum.map(fn {k, v} -> "#{k} #{List.first(v)}" end)
    |> Enum.join(", ")
  end
end
