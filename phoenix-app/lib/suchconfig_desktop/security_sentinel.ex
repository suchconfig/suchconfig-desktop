defmodule SuchConfigDesktop.SecuritySentinel do
  @moduledoc """
  Persist and load Security Sentinel `security_manifest` vault items.

  Scan normalization and grading live in `suchconfig_sentinel_core` (Rust).
  This module stores the resulting JSON report as a CRDT vault item.
  """

  import Ecto.Query

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.Vault.Item

  @kind "security_manifest"
  @title "Security Manifest"

  @doc """
  Upserts the per-folder security manifest from a ScanReport JSON map or string.
  """
  def upsert_manifest(folder_id, report, password)
      when is_integer(folder_id) and is_binary(password) and password != "" do
    with {:ok, report_map} <- coerce_report(report),
         body <- Jason.encode!(report_map),
         frontmatter <- frontmatter_from_report(folder_id, report_map) do
      attrs = %{
        id: existing_manifest_id(folder_id),
        title: @title,
        kind: @kind,
        security_mode: "global_passkey",
        project_folder_id: folder_id,
        body: body,
        frontmatter: frontmatter
      }

      case ProjectVault.save_vault_item(attrs, password) do
        {:ok, _} = ok ->
          ok

        {:error, %Ecto.Changeset{} = changeset} ->
          retry_upsert_on_title_conflict(folder_id, attrs, password, changeset)

        other ->
          other
      end
    end
  end

  def upsert_manifest(_, _, _), do: {:error, :invalid_password}

  @doc """
  Returns the security_manifest vault item for a folder, if any.
  Prefers kind match, then the reserved title `"Security Manifest"`.
  """
  def get_manifest_item(folder_id) when is_integer(folder_id) do
    get_manifest_item_by_kind(folder_id) || get_manifest_item_by_title(folder_id)
  end

  def get_manifest_item(_), do: nil

  @doc """
  Decrypts and returns `{item, report_map}` for the folder manifest.
  """
  def get_manifest(folder_id, password)
      when is_integer(folder_id) and is_binary(password) and password != "" do
    case get_manifest_item(folder_id) do
      nil ->
        {:error, :not_found}

      %Item{} = item ->
        with {:ok, body} <- ProjectVault.decrypt_vault_item_body(item, password),
             {:ok, report} <- decode_report_body(body) do
          {:ok, item, report}
        end
    end
  end

  def get_manifest(_, _), do: {:error, :invalid_password}

  @doc """
  Builds a Report Card assign map from a stored report (no re-grading).
  """
  def report_card_from_report(%{} = report) do
    findings =
      Map.get(report, "top_findings") || Map.get(report, "findings") || []

    summary = Map.get(report, "summary") || %{}

    %{
      overall_grade: Map.get(report, "overall_grade") || "F",
      risk_score: Map.get(report, "risk_score") || 0,
      summary: %{
        critical: Map.get(summary, "critical") || 0,
        high: Map.get(summary, "high") || 0,
        medium: Map.get(summary, "medium") || 0,
        low: Map.get(summary, "low") || 0,
        info: Map.get(summary, "info") || 0
      },
      top_findings: Enum.take(findings, 8),
      recommended_actions: Map.get(report, "recommended_actions") || [],
      last_scan: Map.get(report, "last_scan"),
      scanners: Map.get(report, "scanners") || []
    }
  end

  def report_card_from_report(_), do: nil

  @doc """
  Returns grade/score summary from vault item frontmatter without decrypting body.
  """
  def risk_badge_from_item(%Item{} = item, password) when is_binary(password) do
    with {:ok, grade} <- ProjectVault.vault_item_frontmatter(item, password, "overall_grade"),
         {:ok, score} <- ProjectVault.vault_item_frontmatter(item, password, "risk_score") do
      {:ok,
       %{
         overall_grade: grade || "—",
         risk_score: parse_score(score),
         last_scan:
           case ProjectVault.vault_item_frontmatter(item, password, "last_scan") do
             {:ok, v} -> v
             _ -> nil
           end
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  def risk_badge_from_item(_, _), do: {:error, :unavailable}

  def risk_badge_for_folder(folder_id, password)
      when is_integer(folder_id) and is_binary(password) do
    case get_manifest_item(folder_id) do
      nil -> {:error, :not_found}
      item -> risk_badge_from_item(item, password)
    end
  end

  def risk_badge_for_folder(_, _), do: {:error, :invalid_password}

  defp existing_manifest_id(folder_id) do
    case get_manifest_item(folder_id) do
      %Item{id: id} -> id
      _ -> nil
    end
  end

  defp get_manifest_item_by_kind(folder_id) do
    from(i in Item,
      where: i.project_folder_id == ^folder_id and i.kind == @kind,
      order_by: [desc: i.updated_at, desc: i.id],
      limit: 1
    )
    |> Repo.one()
  end

  defp get_manifest_item_by_title(folder_id) do
    from(i in Item,
      where: i.project_folder_id == ^folder_id and i.title == ^@title,
      order_by: [desc: i.updated_at, desc: i.id],
      limit: 1
    )
    |> Repo.one()
  end

  defp retry_upsert_on_title_conflict(folder_id, attrs, password, changeset) do
    if title_taken?(changeset) do
      case get_manifest_item_by_title(folder_id) || get_manifest_item_by_kind(folder_id) do
        %Item{id: id} ->
          ProjectVault.save_vault_item(Map.put(attrs, :id, id), password)

        _ ->
          {:error, changeset}
      end
    else
      {:error, changeset}
    end
  end

  defp title_taken?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:title, {_msg, opts}} when is_list(opts) ->
        opts[:constraint] == :unique or
          opts[:constraint_name] in [
            :vault_items_project_folder_id_title_index,
            "vault_items_project_folder_id_title_index"
          ]

      {:title, {msg, _opts}} when is_binary(msg) ->
        String.contains?(msg, "has already been taken")

      _ ->
        false
    end)
  end

  defp title_taken?(_), do: false

  defp coerce_report(report) when is_map(report), do: {:ok, stringify_keys(report)}

  defp coerce_report(report) when is_binary(report) do
    case Jason.decode(report) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_report}
    end
  end

  defp coerce_report(_), do: {:error, :invalid_report}

  defp decode_report_body(body) when is_binary(body) do
    trimmed = String.trim(body)

    json =
      cond do
        String.starts_with?(trimmed, "```json") ->
          trimmed
          |> String.trim_leading("```json")
          |> String.trim_trailing("```")
          |> String.trim()

        String.starts_with?(trimmed, "```") ->
          trimmed
          |> String.trim_leading("```")
          |> String.trim_trailing("```")
          |> String.trim()

        true ->
          trimmed
      end

    case Jason.decode(json) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_report}
    end
  end

  defp frontmatter_from_report(folder_id, report) do
    path = Map.get(report, "linked_project_path") || Map.get(report, "path") || ""

    %{
      "folder_id" => Integer.to_string(folder_id),
      "linked_project_path" => to_string(path),
      "last_scan" => to_string(Map.get(report, "last_scan") || ""),
      "risk_score" => to_string(Map.get(report, "risk_score") || 0),
      "overall_grade" => to_string(Map.get(report, "overall_grade") || "F"),
      "scanners" => Jason.encode!(Map.get(report, "scanners") || [])
    }
  end

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), stringify_value(v)}
      {k, v} -> {to_string(k), stringify_value(v)}
    end)
  end

  defp stringify_value(%{} = m), do: stringify_keys(m)
  defp stringify_value(list) when is_list(list), do: Enum.map(list, &stringify_value/1)
  defp stringify_value(other), do: other

  defp parse_score(nil), do: 0
  defp parse_score(n) when is_integer(n), do: n

  defp parse_score(s) when is_binary(s) do
    case Integer.parse(s) do
      {n, _} -> n
      :error -> 0
    end
  end

  defp parse_score(_), do: 0
end
