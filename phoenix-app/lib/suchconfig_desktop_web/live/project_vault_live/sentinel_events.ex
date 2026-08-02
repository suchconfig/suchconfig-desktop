defmodule SuchConfigDesktopWeb.ProjectVaultLive.SentinelEvents do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [push_event: 3, start_async: 3]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.SecuritySentinel

  def start_onboard_scan(socket, path, folder_id)
      when is_binary(path) and is_integer(folder_id) do
    if ProjectVault.security_sentinel_license_enabled?() do
      socket
      |> assign(
        sentinel_scanning: true,
        sentinel_scan_phase: "start",
        sentinel_scan_percent: 5,
        sentinel_scan_message: "Starting Security Sentinel…",
        sentinel_error: nil,
        show_sentinel_report_modal: false,
        sentinel_report_card: nil,
        sentinel_pending_path: path,
        sentinel_pending_folder_id: folder_id
      )
      |> push_event("invoke_sentinel_onboard", %{path: path, folder_id: folder_id})
    else
      show_upgrade(socket)
    end
  end

  def start_onboard_scan(socket, _, _), do: socket

  def start_rescan(socket) do
    if not ProjectVault.security_sentinel_license_enabled?() do
      show_upgrade(socket)
    else
      path = socket.assigns[:sentinel_pending_path] || linked_path(socket)
      folder_id = socket.assigns[:selected_folder_id]

      cond do
        not is_binary(path) or String.trim(path) == "" ->
          assign(socket,
            sentinel_error: "Link a project folder first, then run Sentinel Scan.",
            info: nil,
            show_sentinel_report_modal: true,
            sentinel_scanning: false
          )

        not is_integer(folder_id) ->
          assign(socket, sentinel_error: "Select a project folder first.", info: nil)

        true ->
          socket
          |> assign(
            sentinel_scanning: true,
            sentinel_scan_phase: "start",
            sentinel_scan_percent: 5,
            sentinel_scan_message: "Starting Security Sentinel…",
            sentinel_error: nil,
            show_sentinel_report_modal: false,
            sentinel_pending_path: path,
            sentinel_pending_folder_id: folder_id
          )
          |> push_event("invoke_sentinel_rescan", %{path: path, folder_id: folder_id})
      end
    end
  end

  defp show_upgrade(socket) do
    assign(socket,
      show_sentinel_report_modal: true,
      sentinel_scanning: false,
      sentinel_scan_phase: nil,
      sentinel_scan_percent: 0,
      sentinel_scan_message: nil,
      sentinel_report_card: nil,
      sentinel_error: nil,
      info: nil
    )
  end

  def progress(params, socket) do
    percent =
      case params["percent"] || params[:percent] do
        n when is_integer(n) ->
          n

        n when is_binary(n) ->
          case Integer.parse(n) do
            {v, _} -> v
            :error -> socket.assigns[:sentinel_scan_percent] || 0
          end

        _ ->
          socket.assigns[:sentinel_scan_percent] || 0
      end

    {:noreply,
     assign(socket,
       sentinel_scanning: true,
       sentinel_scan_phase: params["phase"] || params[:phase],
       sentinel_scan_percent: percent,
       sentinel_scan_message: params["message"] || params[:message]
     )}
  end

  def scan_result(params, socket) do
    pw = socket.assigns[:vault_password]

    folder_id =
      parse_folder_id(params["folder_id"] || params[:folder_id]) ||
        socket.assigns[:sentinel_pending_folder_id] || socket.assigns[:selected_folder_id]

    report_path = params["report_path"] || params[:report_path]
    report_card = params["report_card"] || params[:report_card]
    report = params["report"] || params[:report]
    error = params["error"] || params[:error]
    card = SecuritySentinel.report_card_from_report(report_card || report)

    cond do
      is_binary(error) and String.trim(error) != "" ->
        {:noreply,
         assign(socket,
           sentinel_scanning: false,
           sentinel_error: error,
           info: nil
         )}

      not is_integer(folder_id) ->
        {:noreply,
         assign(socket,
           sentinel_scanning: false,
           show_sentinel_report_modal: card != nil,
           sentinel_report_card: card,
           sentinel_error: "Missing folder for Security Manifest.",
           info: nil
         )}

      is_nil(card) and not usable_report_path?(report_path) and not is_map(report) ->
        {:noreply,
         assign(socket,
           sentinel_scanning: false,
           sentinel_error: "Sentinel returned an empty report.",
           info: nil
         )}

      not (is_binary(pw) and String.trim(pw) != "") ->
        {:noreply,
         assign(socket,
           sentinel_scanning: false,
           show_sentinel_report_modal: true,
           sentinel_report_card: card,
           sentinel_error: "Unlock the vault to save the Security Manifest.",
           info: nil
         )}

      true ->
        socket =
          assign(socket,
            sentinel_scanning: true,
            sentinel_scan_percent: 100,
            sentinel_scan_message: "Saving Security Manifest…",
            show_sentinel_report_modal: true,
            sentinel_report_card: card,
            sentinel_error: nil,
            info: nil
          )

        {:noreply,
         start_async(socket, :sentinel_save_manifest, fn ->
           persist_manifest(folder_id, report_path, report, pw)
         end)}
    end
  end

  def save_manifest_done({:ok, {:ok, item, folder_id}}, socket) do
    items = ProjectVault.list_vault_items_by_folder(folder_id)
    card = socket.assigns[:sentinel_report_card]

    badge =
      case card do
        %{overall_grade: _, risk_score: _, last_scan: _} = c ->
          %{overall_grade: c.overall_grade, risk_score: c.risk_score, last_scan: c.last_scan}

        _ ->
          nil
      end

    assign(socket,
      vault_items: items,
      sentinel_scanning: false,
      show_sentinel_report_modal: true,
      sentinel_risk_badge: badge || socket.assigns[:sentinel_risk_badge],
      sentinel_manifest_item_id: item.id,
      sentinel_error: nil,
      info: "Security Sentinel scan complete."
    )
  end

  def save_manifest_done({:ok, {:error, reason}}, socket) do
    assign(socket,
      sentinel_scanning: false,
      show_sentinel_report_modal: true,
      sentinel_error: "Scan finished but could not save manifest: #{format_err(reason)}",
      info: nil
    )
  end

  def save_manifest_done({:exit, reason}, socket) do
    assign(socket,
      sentinel_scanning: false,
      show_sentinel_report_modal: true,
      sentinel_error: "Scan finished but could not save manifest: #{inspect(reason)}",
      info: nil
    )
  end

  def close_report_modal(socket) do
    assign(socket, show_sentinel_report_modal: false)
  end

  def open_manifest_item(socket) do
    item_id = socket.assigns[:sentinel_manifest_item_id]
    pw = socket.assigns[:vault_password]
    folder_id = socket.assigns[:selected_folder_id]

    case item_id && ProjectVault.get_vault_item(item_id) do
      %{id: id, title: title, kind: kind} = item ->
        body =
          case ProjectVault.decrypt_vault_item_body(item, pw || "") do
            {:ok, b} -> b
            _ -> ""
          end

        items =
          if is_integer(folder_id) do
            ProjectVault.list_vault_items_by_folder(folder_id)
          else
            socket.assigns[:vault_items] || []
          end

        assign(socket,
          show_sentinel_report_modal: false,
          vault_items: items,
          selected_vault_item_id: id,
          selected_note_id: nil,
          editor_focus: :vault_item,
          note_title: title,
          note_raw_content: body,
          note_category: kind
        )

      _ ->
        assign(socket, show_sentinel_report_modal: false, info: "Security Manifest not found.")
    end
  end

  def open_report_from_manifest(socket) do
    body = socket.assigns[:note_raw_content]

    case decode_manifest_body(body) do
      {:ok, report} ->
        card = SecuritySentinel.report_card_from_report(report)

        assign(socket,
          show_sentinel_report_modal: true,
          sentinel_report_card: card,
          sentinel_scanning: false,
          sentinel_error: nil,
          info: nil
        )

      {:error, _} ->
        assign(socket,
          sentinel_error: nil,
          info: "Could not open Report Card — Security Manifest JSON is invalid."
        )
    end
  end

  def load_risk_badge(socket) do
    folder_id = socket.assigns[:selected_folder_id]
    pw = socket.assigns[:vault_password]

    badge =
      if is_integer(folder_id) and is_binary(pw) and pw != "" do
        case SecuritySentinel.risk_badge_for_folder(folder_id, pw) do
          {:ok, b} -> b
          _ -> nil
        end
      else
        nil
      end

    assign(socket, sentinel_risk_badge: badge)
  end

  defp persist_manifest(folder_id, report_path, report, password) do
    with {:ok, report_map} <- load_report(report_path, report),
         {:ok, item} <- SecuritySentinel.upsert_manifest(folder_id, report_map, password) do
      maybe_cleanup_report_path(report_path)
      {:ok, item, folder_id}
    else
      {:error, reason} ->
        maybe_cleanup_report_path(report_path)
        {:error, reason}
    end
  end

  defp load_report(report_path, _report) when is_binary(report_path) and report_path != "" do
    with {:ok, body} <- File.read(report_path),
         {:ok, map} when is_map(map) <- Jason.decode(body) do
      {:ok, map}
    else
      {:ok, _} -> {:error, :invalid_report}
      {:error, reason} -> {:error, reason}
    end
  end

  defp load_report(_report_path, report) when is_map(report), do: {:ok, report}
  defp load_report(_, _), do: {:error, :invalid_report}

  defp decode_manifest_body(body) when is_binary(body) do
    case Jason.decode(body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      {:ok, _} -> {:error, :invalid_report}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_manifest_body(_), do: {:error, :invalid_report}

  defp usable_report_path?(path) when is_binary(path), do: String.trim(path) != ""
  defp usable_report_path?(_), do: false

  defp maybe_cleanup_report_path(path) when is_binary(path) and path != "" do
    tmp = Path.expand(System.tmp_dir!())
    expanded = Path.expand(path)

    if String.starts_with?(expanded, tmp <> "/") or expanded == tmp do
      _ = File.rm(expanded)
    end

    :ok
  end

  defp maybe_cleanup_report_path(_), do: :ok

  defp linked_path(socket) do
    folder_id = socket.assigns[:selected_folder_id]
    folders = socket.assigns[:folders] || []

    case Enum.find(folders, &(&1.id == folder_id)) do
      %{linked_project_path: path} when is_binary(path) -> path
      _ -> nil
    end
  end

  defp parse_folder_id(nil), do: nil
  defp parse_folder_id(id) when is_integer(id), do: id

  defp parse_folder_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, _} -> n
      :error -> nil
    end
  end

  defp parse_folder_id(_), do: nil

  defp format_err(reason), do: ProjectVault.format_error(reason)
end
