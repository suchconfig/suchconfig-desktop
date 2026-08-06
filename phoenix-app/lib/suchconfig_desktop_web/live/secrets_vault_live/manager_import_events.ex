defmodule SuchConfigDesktopWeb.SecretsVaultLive.ManagerImportEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, upload_errors: 2]
  import Phoenix.LiveView, only: [consume_uploaded_entries: 3, cancel_upload: 3]

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.SecretsVault.ManagerImport
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData

  def open_wizard(_params, socket) do
    if socket.assigns.global_passkey_unlocked do
      {:noreply,
       assign(socket,
         manager_import_open: true,
         manager_import_stage: :source,
         manager_import_preview: nil,
         manager_import_result: nil,
         manager_import_duplicate_strategy: :keep_as_new,
         error: nil,
         info: nil
       )}
    else
      {:noreply, assign(socket, error: "Unlock Secrets Vault before importing.", info: nil)}
    end
  end

  def close_wizard(_params, socket) do
    {:noreply, reset_wizard(socket)}
  end

  def choose_source(%{"source" => "bitwarden"}, socket) do
    {:noreply,
     assign(socket,
       manager_import_stage: :file,
       manager_import_preview: nil,
       manager_import_result: nil,
       manager_import_duplicate_strategy: :keep_as_new,
       error: nil
     )}
  end

  def choose_source(_params, socket) do
    {:noreply, assign(socket, error: "That manager is not available yet.", info: nil)}
  end

  def set_duplicate_strategy(%{"strategy" => strategy}, socket) do
    strategy =
      case strategy do
        "overwrite" -> :overwrite
        _ -> :keep_as_new
      end

    {:noreply, assign(socket, manager_import_duplicate_strategy: strategy, error: nil)}
  end

  def set_duplicate_strategy(_params, socket), do: {:noreply, socket}

  def validate_upload(_params, socket) do
    {:noreply, assign(socket, error: nil, info: nil)}
  end

  def back_to_source(_params, socket) do
    socket = cancel_pending_uploads(socket)

    {:noreply,
     assign(socket,
       manager_import_stage: :source,
       manager_import_preview: nil,
       manager_import_duplicate_strategy: :keep_as_new,
       error: nil
     )}
  end

  def prepare_preview(_params, socket) do
    upload = socket.assigns.uploads.manager_import_file

    cond do
      upload.entries == [] ->
        {:noreply, assign(socket, error: "Select a Bitwarden JSON export file.", info: nil)}

      not Enum.any?(upload.entries, & &1.done?) ->
        {:noreply,
         assign(socket,
           error: "Wait for the file to finish uploading, then try again.",
           info: nil
         )}

      (errors =
         upload.entries
         |> Enum.flat_map(fn entry -> upload_errors(upload, entry) end)) != [] ->
        {:noreply, assign(socket, error: "Upload failed: #{inspect(errors)}", info: nil)}

      not Enum.any?(upload.entries, &json_export_name?/1) ->
        {:noreply,
         assign(socket,
           error: "Only Bitwarden unencrypted .json exports are supported.",
           info: nil
         )}

      true ->
        uploaded =
          consume_uploaded_entries(socket, :manager_import_file, fn %{path: path}, _entry ->
            {:ok, File.read!(path)}
          end)

        case uploaded do
          [payload | _] when is_binary(payload) ->
            case ManagerImport.preview_bitwarden_export(payload) do
              {:ok, preview} ->
                {:noreply,
                 assign(socket,
                   manager_import_preview: preview,
                   manager_import_stage: :preview,
                   manager_import_duplicate_strategy: :keep_as_new,
                   error: nil,
                   info: nil
                 )}

              {:error, :encrypted_export} ->
                {:noreply,
                 assign(socket,
                   error:
                     "This export is encrypted. In Bitwarden use Tools → Export vault → JSON (unencrypted).",
                   info: nil
                 )}

              {:error, reason} ->
                {:noreply,
                 assign(socket,
                   error: "Could not parse export: #{SecretsVault.format_error(reason)}",
                   info: nil
                 )}
            end

          _ ->
            {:noreply, assign(socket, error: "Could not read the uploaded file.", info: nil)}
        end
    end
  end

  def confirm_import(_params, socket) do
    password = socket.assigns[:vault_password]
    preview = socket.assigns.manager_import_preview
    strategy = socket.assigns[:manager_import_duplicate_strategy] || :keep_as_new

    cond do
      not is_binary(password) or password == "" ->
        {:noreply, assign(socket, error: "Unlock Secrets Vault before importing.", info: nil)}

      is_nil(preview) or is_nil(preview.import_data) ->
        {:noreply, assign(socket, error: "Nothing to import. Preview the file first.", info: nil)}

      preview.duplicate_count > 0 and strategy not in [:overwrite, :keep_as_new] ->
        {:noreply, assign(socket, error: "Choose how to handle duplicate items.", info: nil)}

      true ->
        case ManagerImport.import_normalized(preview.import_data, :all, password,
               duplicate_strategy: strategy
             ) do
          {:ok, result} ->
            info = import_success_message(result)

            socket =
              socket
              |> assign(
                manager_import_result: result,
                manager_import_stage: :done,
                manager_import_preview: preview,
                info: info,
                error: nil,
                folders: SecretsVault.list_folders()
              )
              |> ViewData.assign_view_data()

            {:noreply, socket}

          {:error, reason} ->
            {:noreply,
             assign(socket,
               error: "Import failed: #{SecretsVault.format_error(reason)}",
               info: nil
             )}
        end
    end
  end

  defp import_success_message(result) do
    parts = ["Imported #{result.imported} secrets from Bitwarden"]

    parts =
      if result.overwritten > 0 do
        parts ++ ["#{result.overwritten} overwritten"]
      else
        parts
      end

    parts =
      if result.created > 0 and result.overwritten > 0 do
        parts ++ ["#{result.created} created"]
      else
        parts
      end

    Enum.join(parts, " · ") <> "."
  end

  defp reset_wizard(socket) do
    socket
    |> cancel_pending_uploads()
    |> assign(
      manager_import_open: false,
      manager_import_stage: :idle,
      manager_import_preview: nil,
      manager_import_result: nil,
      manager_import_duplicate_strategy: :keep_as_new
    )
  end

  defp cancel_pending_uploads(socket) do
    case socket.assigns[:uploads] do
      %{manager_import_file: upload} ->
        Enum.reduce(upload.entries, socket, fn entry, acc ->
          cancel_upload(acc, :manager_import_file, entry.ref)
        end)

      _ ->
        socket
    end
  end

  defp json_export_name?(%{client_name: name}) when is_binary(name) do
    name |> String.downcase() |> String.ends_with?(".json")
  end

  defp json_export_name?(_), do: false
end
