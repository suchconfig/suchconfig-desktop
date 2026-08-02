defmodule SuchConfigDesktop.VaultStorage do
  @moduledoc """
  Local SQLite storage summary for Settings (disk footprint and item counts).
  """

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.EnvManager.{Note, ProjectFolder}
  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault.{Folder, Item}
  alias SuchConfigDesktop.Vault.Item, as: VaultItem
  alias SuchConfigDesktop.VaultMergeAuditEvent

  @type summary :: %{
          bytes_on_disk: non_neg_integer(),
          size_value: String.t(),
          size_unit: String.t(),
          secure_note_count: non_neg_integer(),
          secrets_count: non_neg_integer(),
          project_count: non_neg_integer(),
          secrets_folder_count: non_neg_integer(),
          archive_event_count: non_neg_integer(),
          breakdown_label: String.t()
        }

  @spec summary() :: summary()
  def summary do
    secure_note_count = count(VaultItem) + count(Note)
    secrets_count = count(Item)
    project_count = count(ProjectFolder)
    secrets_folder_count = count(Folder)
    archive_event_count = archive_event_count()
    bytes = database_bytes_on_disk()
    {size_value, size_unit} = format_size(bytes)

    %{
      bytes_on_disk: bytes,
      size_value: size_value,
      size_unit: size_unit,
      secure_note_count: secure_note_count,
      secrets_count: secrets_count,
      project_count: project_count,
      secrets_folder_count: secrets_folder_count,
      archive_event_count: archive_event_count,
      breakdown_label:
        breakdown_label(
          secure_note_count,
          secrets_count,
          project_count,
          archive_event_count
        )
    }
  end

  @spec database_path() :: String.t() | nil
  def database_path do
    case Repo.config()[:database] do
      path when is_binary(path) and path != "" -> Path.expand(path)
      _ -> nil
    end
  end

  @spec database_bytes_on_disk() :: non_neg_integer()
  def database_bytes_on_disk do
    case database_path() do
      nil ->
        0

      path ->
        [path, path <> "-wal", path <> "-shm"]
        |> Enum.map(&file_size/1)
        |> Enum.sum()
    end
  end

  @spec format_size(non_neg_integer()) :: {String.t(), String.t()}
  def format_size(bytes) when is_integer(bytes) and bytes < 0, do: format_size(0)

  def format_size(bytes) when is_integer(bytes) do
    cond do
      bytes < 1024 ->
        {Integer.to_string(bytes), "B"}

      bytes < 1024 * 1024 ->
        {format_number(bytes / 1024), "KB"}

      bytes < 1024 * 1024 * 1024 ->
        {format_number(bytes / (1024 * 1024)), "MB"}

      true ->
        {format_number(bytes / (1024 * 1024 * 1024)), "GB"}
    end
  end

  defp count(schema) do
    Repo.aggregate(schema, :count, :id) || 0
  end

  defp archive_event_count do
    from(e in VaultMergeAuditEvent,
      where: e.operation in ["export", "import"],
      select: count(e.id)
    )
    |> Repo.one()
    |> Kernel.||(0)
  end

  defp breakdown_label(secure_notes, secrets, projects, archives) do
    [
      pluralize(secure_notes, "secure note", "secure notes"),
      pluralize(secrets, "secret", "secrets"),
      pluralize(projects, "project", "projects"),
      pluralize(archives, "archive", "archives")
    ]
    |> Enum.join(" · ")
  end

  defp pluralize(1, singular, _plural), do: "1 #{singular}"
  defp pluralize(count, _singular, plural), do: "#{count} #{plural}"

  defp file_size(path) do
    case File.stat(path) do
      {:ok, %{size: size}} when is_integer(size) and size >= 0 -> size
      _ -> 0
    end
  end

  defp format_number(value) when value >= 10 do
    value |> Float.round(0) |> trunc() |> Integer.to_string()
  end

  defp format_number(value) do
    formatted = :erlang.float_to_binary(value * 1.0, decimals: 1)

    if String.ends_with?(formatted, ".0") do
      String.trim_trailing(formatted, ".0")
    else
      formatted
    end
  end
end
