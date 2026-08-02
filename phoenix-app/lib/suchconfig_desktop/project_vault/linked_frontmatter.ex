defmodule SuchConfigDesktop.ProjectVault.LinkedFrontmatter do
  @moduledoc false

  @relative_path "linked_relative_path"
  @content_sha256 "linked_content_sha256"
  @disk_mtime "linked_disk_mtime"
  @sync_mode "linked_sync_mode"
  @last_synced_at "linked_last_synced_at"

  def relative_path, do: @relative_path
  def content_sha256, do: @content_sha256
  def disk_mtime, do: @disk_mtime
  def sync_mode, do: @sync_mode
  def last_synced_at, do: @last_synced_at

  def agreement_keys,
    do: [@relative_path, @content_sha256, @disk_mtime, @sync_mode, @last_synced_at]

  def import_bundle(relative_path, body, disk_mtime) when is_binary(relative_path) do
    %{
      @relative_path => relative_path,
      @content_sha256 => content_fingerprint(body),
      @disk_mtime => Integer.to_string(disk_mtime),
      @sync_mode => "manual",
      @last_synced_at => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def after_agreement(body, disk_mtime) do
    %{
      @content_sha256 => content_fingerprint(body),
      @disk_mtime => Integer.to_string(disk_mtime),
      @last_synced_at => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  def content_fingerprint(body) when is_binary(body) do
    body
    |> normalize_body()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def normalize_body(body) when is_binary(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.replace("\r", "\n")
  end

  def disk_file_fingerprint(path) when is_binary(path) do
    with {:ok, body} <- File.read(path),
         true <- String.valid?(body),
         {:ok, mtime} <- file_mtime_seconds(path) do
      {:ok, content_fingerprint(body), mtime, body}
    else
      _ -> :error
    end
  end

  def file_mtime_seconds(path) do
    case File.stat(path, time: :posix) do
      {:ok, %{mtime: mtime}} -> {:ok, mtime}
      _ -> {:error, :stat}
    end
  end
end
