defmodule SuchConfigDesktopWeb.TrustedFolderEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [connected?: 1, put_flash: 3, push_event: 3]

  alias SuchConfigDesktop.TrustedFolder
  alias SuchConfigDesktop.VaultKeyStore
  alias SuchConfigDesktop.VaultSessionRegistry

  @vault_key_id "suchconfig.project_manager.vault"

  def default_assigns do
    [
      trusted_folder_path: nil,
      trusted_folder_display_path: nil,
      trusted_folder_watcher_running: false,
      trusted_folder_synced: false,
      trusted_folder_sync_busy: false,
      trusted_folder_last_error: nil,
      trusted_folder_integrity_message: nil,
      show_trusted_folder_modal: false,
      trusted_folder_modal_busy: false,
      trusted_folder_modal_error: nil,
      trusted_folder_changing_path: false,
      trusted_folder_startup_sync_done: false
    ]
  end

  def on_mount_connected(socket) do
    refresh_status(socket)
  end

  def refresh_status(socket) do
    if connected?(socket) do
      push_event(socket, "fetch_trusted_folder", %{})
    else
      socket
    end
  end

  def apply_status(socket, params) when is_map(params) do
    resolved_path = resolve_path(params, socket)

    path =
      if TrustedFolder.configured?(resolved_path) do
        resolved_path
      else
        socket.assigns[:trusted_folder_path]
      end

    watcher? = resolve_watcher(params, socket)
    backed_up? = resolve_backed_up(params, socket)

    display =
      if TrustedFolder.configured?(path) do
        TrustedFolder.display_path(path)
      else
        socket.assigns[:trusted_folder_display_path]
      end

    configured? = TrustedFolder.configured?(path)

    show_modal =
      !configured? and !socket.assigns[:show_unlock_overlay] and
        !(socket.assigns[:vault_skipped] == true)

    broadcast_status(
      status_from_socket(
        socket,
        %{
          "trusted_folder_path" => path,
          "watcher_running" => watcher?,
          "projects_enc_present" => backed_up?,
          "secrets_enc_present" => backed_up?
        }
      )
    )

    socket
    |> assign(
      trusted_folder_path: path,
      trusted_folder_display_path: display,
      trusted_folder_watcher_running: watcher?,
      trusted_folder_synced: backed_up?,
      show_trusted_folder_modal: show_modal
    )
    |> maybe_push_backup_if_missing(backed_up?, watcher?, configured?)
    |> push_startup_sync_if_ready(configured?, watcher?)
  end

  def apply_status(socket, _), do: socket

  def handle_setup_complete(socket, params) when is_map(params) do
    path = params["trusted_folder_path"] || params[:trusted_folder_path]
    display = TrustedFolder.display_path(path)

    socket =
      socket
      |> assign(
        trusted_folder_path: path,
        trusted_folder_display_path: display,
        trusted_folder_watcher_running: true,
        trusted_folder_synced: false,
        show_trusted_folder_modal: false,
        trusted_folder_modal_busy: false,
        trusted_folder_modal_error: nil,
        trusted_folder_last_error: nil,
        trusted_folder_changing_path: false
      )
      |> put_flash(:info, setup_complete_flash_message(socket))

    broadcast_status(%{
      "trusted_folder_path" => path,
      "watcher_running" => true,
      "last_error" => nil,
      "sync_busy" => false,
      "integrity_message" => nil
    })

    maybe_push_initial_export(socket, params)
  end

  def handle_setup_complete(socket, _), do: socket

  def handle_synced(socket, _params) do
    broadcast_status(
      status_from_socket(socket, %{
        "watcher_running" => true,
        "projects_enc_present" => true,
        "secrets_enc_present" => true,
        "last_error" => nil,
        "sync_busy" => false
      })
    )

    socket
    |> assign(
      trusted_folder_synced: true,
      trusted_folder_watcher_running: true,
      trusted_folder_sync_busy: false,
      trusted_folder_last_error: nil
    )
    |> refresh_status()
    |> put_flash(:info, "Trusted Folder backup synced.")
  end

  def handle_sync_failed(socket, %{"message" => message}) when is_binary(message) do
    trimmed = String.trim(message)
    error = if trimmed == "", do: "Trusted Folder sync failed.", else: trimmed

    socket
    |> assign(trusted_folder_sync_busy: false, trusted_folder_last_error: error)
    |> broadcast_health()
    |> put_flash(:error, error)
  end

  def handle_sync_failed(socket, _params) do
    handle_sync_failed(socket, %{"message" => "Trusted Folder sync failed."})
  end

  def handle_verify_result(socket, params) when is_map(params) do
    message = format_integrity_message(params)

    socket
    |> assign(trusted_folder_integrity_message: message, trusted_folder_last_error: nil)
    |> broadcast_health()
    |> then(fn s ->
      if truthy?(Map.get(params, "all_ok", params["allOk"])) do
        put_flash(s, :info, message)
      else
        put_flash(s, :error, message)
      end
    end)
  end

  def handle_verify_result(socket, _), do: socket

  def handle_request_initial_export(socket, _params) do
    push_full_sync(socket)
  end

  def handle_import_snapshot(socket, %{"vault" => vault} = params) do
    b64 = params["snapshot_base64"] || params["snapshotBase64"]

    with vault_atom when not is_nil(vault_atom) <- TrustedFolder.vault_atom(vault),
         {:ok, binary} <- Base.decode64(String.trim(b64 || "")),
         {:ok, stats} <- TrustedFolder.import_bundle(binary, vault_atom) do
      label = if vault_atom == :projects, do: "Project Vault", else: "Secrets Vault"

      socket =
        if vault_atom == :projects do
          assign(socket, folders: SuchConfigDesktop.ProjectVault.list_project_folders())
        else
          socket
        end

      socket
      |> assign(trusted_folder_last_error: nil)
      |> broadcast_health()
      |> put_flash(:info, import_flash_message(label, stats))
    else
      {:error, :invalid_bundle} ->
        record_error(socket, "Trusted Folder snapshot format was not recognized.")

      _ ->
        record_error(socket, "Could not merge Trusted Folder snapshot.")
    end
  end

  def handle_import_snapshot(socket, _), do: socket

  def open_modal(socket) do
    assign(socket,
      show_trusted_folder_modal: true,
      trusted_folder_changing_path: false,
      trusted_folder_modal_error: nil,
      trusted_folder_modal_busy: false
    )
  end

  def open_change_modal(socket) do
    assign(socket,
      show_trusted_folder_modal: true,
      trusted_folder_changing_path: true,
      trusted_folder_modal_error: nil,
      trusted_folder_modal_busy: false
    )
  end

  def close_modal(socket) do
    assign(socket,
      show_trusted_folder_modal: false,
      trusted_folder_modal_busy: false,
      trusted_folder_modal_error: nil,
      trusted_folder_changing_path: false
    )
  end

  def begin_setup(socket) do
    force_picker = socket.assigns[:trusted_folder_changing_path] == true

    socket
    |> assign(trusted_folder_modal_busy: true, trusted_folder_modal_error: nil)
    |> push_event("invoke_setup_trusted_folder", %{force_picker: force_picker})
  end

  def request_sync_now(socket) do
    if ready_to_sync?(socket) and connected?(socket) do
      socket
      |> assign(trusted_folder_sync_busy: true, trusted_folder_last_error: nil)
      |> broadcast_health()
      |> push_full_sync()
    else
      record_error(socket, sync_blocked_message(socket))
    end
  end

  def request_verify_integrity(socket) do
    if TrustedFolder.configured?(socket.assigns[:trusted_folder_path]) and connected?(socket) do
      payload =
        %{}
        |> maybe_put_master_key(socket)

      push_event(socket, "verify_trusted_folder_integrity", payload)
    else
      record_error(socket, "Choose a Trusted Folder before verifying backups.")
    end
  end

  def push_full_sync(socket) do
    vaults =
      [:projects, :secrets]
      |> Enum.flat_map(fn vault ->
        case TrustedFolder.export_bundle(vault) do
          {:ok, binary} ->
            [
              %{
                vault: Atom.to_string(vault),
                snapshot_base64: Base.encode64(binary),
                final: vault == :secrets
              }
            ]

          _ ->
            []
        end
      end)

    if vaults == [] do
      record_error(socket, "Could not export vault snapshots for sync.")
    else
      push_sync_payload(socket, vaults)
    end
  end

  def push_single_vault_sync(socket, vault) when vault in ["projects", "secrets"] do
    case TrustedFolder.vault_atom(vault) do
      nil ->
        socket

      vault_atom ->
        case TrustedFolder.export_bundle(vault_atom) do
          {:ok, binary} ->
            push_sync_payload(socket, [
              %{
                vault: vault,
                snapshot_base64: Base.encode64(binary),
                final: true
              }
            ])

          _ ->
            record_error(socket, "Could not export #{vault} vault snapshot.")
        end
    end
  end

  def broadcast_sync(vault_session_id, vault) when is_binary(vault_session_id) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      "vault:#{vault_session_id}",
      {:trusted_folder_sync, vault}
    )
  end

  def broadcast_sync(_, _), do: :ok

  def notify_projects_changed(socket) do
    if ready_to_sync?(socket) and connected?(socket) do
      push_single_vault_sync(socket, "projects")
    else
      broadcast_sync(socket.assigns[:vault_session_id], "projects")
      socket
    end
  end

  def push_full_sync_if_ready(socket) do
    if ready_to_sync?(socket) and connected?(socket) do
      push_full_sync(socket)
    else
      socket
    end
  end

  def ready_to_sync?(socket) do
    TrustedFolder.configured?(socket.assigns[:trusted_folder_path]) and
      socket.assigns[:trusted_folder_watcher_running] == true and
      socket.assigns[:vault_unlocked] == true
  end

  def apply_status_to_settings(socket, params) when is_map(params) do
    resolved_path = resolve_path(params, socket)

    path =
      if TrustedFolder.configured?(resolved_path) do
        resolved_path
      else
        socket.assigns[:trusted_folder_path]
      end

    display =
      if TrustedFolder.configured?(path) do
        TrustedFolder.display_path(path)
      else
        socket.assigns[:trusted_folder_display_path]
      end

    assign(socket,
      trusted_folder_path: path,
      trusted_folder_display_path: display,
      trusted_folder_synced: resolve_backed_up(params, socket),
      trusted_folder_watcher_running: resolve_watcher(params, socket),
      trusted_folder_sync_busy: resolve_sync_busy(params, socket),
      trusted_folder_last_error: resolve_last_error(params, socket),
      trusted_folder_integrity_message: resolve_integrity_message(params, socket)
    )
  end

  def apply_status_to_settings(socket, _), do: socket

  defp maybe_push_initial_export(socket, params) do
    needs? =
      params["needs_initial_export"] == true or
        params["needs_initial_export"] == "true" or
        is_map(params["archive_paths"])

    if needs? do
      push_full_sync(socket)
    else
      push_full_sync(socket)
    end
  end

  defp blank_to_nil(nil), do: nil
  defp blank_to_nil(""), do: nil
  defp blank_to_nil(s) when is_binary(s), do: String.trim(s)
  defp blank_to_nil(s), do: s

  defp broadcast_status(params) when is_map(params) do
    Phoenix.PubSub.broadcast(
      SuchConfigDesktop.PubSub,
      "trusted_folder:status",
      {:trusted_folder_status, params}
    )
  end

  defp broadcast_health(socket) do
    broadcast_status(status_from_socket(socket))
    socket
  end

  defp record_error(socket, message) when is_binary(message) do
    socket
    |> assign(trusted_folder_last_error: message, trusted_folder_sync_busy: false)
    |> broadcast_health()
    |> put_flash(:error, message)
  end

  defp push_sync_payload(socket, []), do: socket

  defp push_sync_payload(socket, vaults) when is_list(vaults) do
    payload =
      %{vaults: vaults}
      |> maybe_put_master_key(socket)

    push_event(socket, "trusted_folder_push_sync", payload)
  end

  defp maybe_put_master_key(payload, socket) do
    case session_master_key(socket) do
      key when is_binary(key) -> Map.put(payload, :master_key, key)
      _ -> payload
    end
  end

  defp session_master_key(socket) do
    session_id = socket.assigns[:vault_session_id]

    key =
      cond do
        is_binary(session_id) ->
          VaultSessionRegistry.get(session_id) || VaultKeyStore.get(@vault_key_id)

        true ->
          VaultKeyStore.get(@vault_key_id)
      end

    if is_binary(key) and String.trim(key) != "", do: key, else: nil
  end

  defp maybe_push_backup_if_missing(socket, true, _watcher?, _configured?), do: socket

  defp maybe_push_backup_if_missing(socket, false, true, true) do
    if connected?(socket) and socket.assigns[:vault_unlocked] == true do
      push_full_sync(socket)
    else
      socket
    end
  end

  defp maybe_push_backup_if_missing(socket, _backed_up?, _watcher?, _configured?), do: socket

  defp push_startup_sync_if_ready(socket, true, true) do
    if connected?(socket) and ready_to_sync?(socket) and
         socket.assigns[:trusted_folder_startup_sync_done] != true do
      socket
      |> assign(trusted_folder_startup_sync_done: true)
      |> push_full_sync()
    else
      socket
    end
  end

  defp push_startup_sync_if_ready(socket, _configured?, _watcher?), do: socket

  defp status_from_socket(socket, overrides \\ %{}) when is_map(overrides) do
    base = %{
      "trusted_folder_path" => socket.assigns[:trusted_folder_path],
      "watcher_running" => socket.assigns[:trusted_folder_watcher_running],
      "projects_enc_present" => socket.assigns[:trusted_folder_synced],
      "secrets_enc_present" => socket.assigns[:trusted_folder_synced],
      "last_error" => socket.assigns[:trusted_folder_last_error],
      "sync_busy" => socket.assigns[:trusted_folder_sync_busy],
      "integrity_message" => socket.assigns[:trusted_folder_integrity_message]
    }

    Map.merge(base, overrides)
  end

  defp resolve_path(params, socket) when is_map(params) do
    params
    |> param("trusted_folder_path", "trustedFolderPath")
    |> blank_to_nil()
    |> case do
      nil -> blank_to_nil(socket.assigns[:trusted_folder_path])
      path -> path
    end
  end

  defp resolve_watcher(params, socket) when is_map(params) do
    if param_present?(params, "watcher_running", "watcherRunning") do
      truthy?(param(params, "watcher_running", "watcherRunning"))
    else
      socket.assigns[:trusted_folder_watcher_running] == true
    end
  end

  defp resolve_backed_up(params, socket) when is_map(params) do
    if enc_status_in_params?(params) do
      backups_present?(params)
    else
      socket.assigns[:trusted_folder_synced] == true
    end
  end

  defp resolve_sync_busy(params, socket) when is_map(params) do
    if param_present?(params, "sync_busy", "syncBusy") do
      truthy?(param(params, "sync_busy", "syncBusy"))
    else
      socket.assigns[:trusted_folder_sync_busy] == true
    end
  end

  defp resolve_last_error(params, socket) when is_map(params) do
    if param_present?(params, "last_error", "lastError") do
      blank_to_nil(param(params, "last_error", "lastError"))
    else
      socket.assigns[:trusted_folder_last_error]
    end
  end

  defp resolve_integrity_message(params, socket) when is_map(params) do
    if param_present?(params, "integrity_message", "integrityMessage") do
      blank_to_nil(param(params, "integrity_message", "integrityMessage"))
    else
      socket.assigns[:trusted_folder_integrity_message]
    end
  end

  defp param(params, snake, camel) when is_map(params) do
    Map.get(params, snake) || Map.get(params, camel) || Map.get(params, String.to_atom(snake))
  end

  defp param_present?(params, snake, camel) when is_map(params) do
    Map.has_key?(params, snake) || Map.has_key?(params, camel) ||
      Map.has_key?(params, String.to_atom(snake))
  end

  defp enc_status_in_params?(params) when is_map(params) do
    param_present?(params, "projects_enc_present", "projectsEncPresent") and
      param_present?(params, "secrets_enc_present", "secretsEncPresent")
  end

  defp backups_present?(params) when is_map(params) do
    truthy?(param(params, "projects_enc_present", "projectsEncPresent")) and
      truthy?(param(params, "secrets_enc_present", "secretsEncPresent"))
  end

  defp truthy?(true), do: true
  defp truthy?("true"), do: true
  defp truthy?("1"), do: true
  defp truthy?(_), do: false

  defp sync_blocked_message(socket) do
    cond do
      !TrustedFolder.configured?(socket.assigns[:trusted_folder_path]) ->
        "Choose a Trusted Folder before syncing."

      socket.assigns[:trusted_folder_watcher_running] != true ->
        "Trusted Folder watcher is not running."

      socket.assigns[:vault_unlocked] != true ->
        "Unlock your vault to sync encrypted backups."

      true ->
        "Trusted Folder sync is unavailable right now."
    end
  end

  defp import_flash_message(label, %{upserted: upserted, deleted_folders: df, deleted_items: di}) do
    parts =
      ["merged #{upserted} item(s)"]
      |> maybe_add_part(df, "removed #{df} folder(s)")
      |> maybe_add_part(di, "removed #{di} item(s)")

    "Trusted Folder #{Enum.join(parts, ", ")} in #{label}."
  end

  defp maybe_add_part(parts, 0, _text), do: parts

  defp maybe_add_part(parts, count, text) when is_integer(count) and count > 0,
    do: parts ++ [text]

  defp maybe_add_part(parts, _, _text), do: parts

  defp format_integrity_message(%{"all_ok" => true}),
    do: "Backup integrity verified for both vault snapshots."

  defp format_integrity_message(%{"allOk" => true}),
    do: "Backup integrity verified for both vault snapshots."

  defp format_integrity_message(params) do
    issues =
      ["projects", "secrets"]
      |> Enum.flat_map(fn vault ->
        report = Map.get(params, vault) || Map.get(params, String.to_atom(vault)) || %{}

        case report["error"] || report[:error] do
          nil -> []
          "" -> []
          msg -> ["#{vault}: #{msg}"]
        end
      end)

    case issues do
      [] -> "Backup integrity check found issues."
      list -> "Backup integrity issues — " <> Enum.join(list, "; ")
    end
  end

  defp setup_complete_flash_message(%{assigns: %{trusted_folder_changing_path: true}}) do
    "Trusted Folder location updated. Encrypted snapshots will sync to the new folder."
  end

  defp setup_complete_flash_message(_socket) do
    "Trusted Folder activated. Encrypted snapshots export on save and import when backup files change on disk."
  end
end
