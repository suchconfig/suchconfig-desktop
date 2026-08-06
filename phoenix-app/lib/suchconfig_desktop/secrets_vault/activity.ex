defmodule SuchConfigDesktop.SecretsVault.Activity do
  @moduledoc false

  alias SuchConfigDesktop.SecretsVault.ActivityEvent
  alias SuchConfigDesktop.SecretsVault.Item
  alias SuchConfigDesktop.Repo

  import Ecto.Query, warn: false

  @frontmatter_labels %{
    "username" => "Updated username",
    "url" => "Updated URL",
    "public_key" => "Updated public key",
    "fingerprint" => "Updated fingerprint",
    "hostname" => "Updated hostname",
    "tags" => "Updated tags",
    "project_ref" => "Updated project ref",
    "totp" => "Updated TOTP",
    "notes" => "Updated notes"
  }

  def record(item_id, action, summary, metadata \\ %{})

  def record(item_id, action, summary, metadata)
      when is_integer(item_id) and is_binary(action) and is_binary(summary) and is_map(metadata) do
    if action != "create" do
      ensure_create_event(item_id)
    end

    attrs = %{
      secrets_vault_item_id: item_id,
      action: action,
      summary: summary,
      device_label: device_label(),
      metadata: metadata
    }

    case %ActivityEvent{}
         |> ActivityEvent.changeset(attrs)
         |> Repo.insert() do
      {:ok, event} -> {:ok, event}
      {:error, _} -> :ok
    end
  end

  def record(_, _, _, _), do: :ok

  def list(item_id, limit \\ 20)

  def list(item_id, limit) when is_integer(item_id) and is_integer(limit) and limit > 0 do
    from(e in ActivityEvent,
      where: e.secrets_vault_item_id == ^item_id,
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: ^limit
    )
    |> Repo.all()
  end

  def list(_, _), do: []

  def latest_copy_at(item_id) when is_integer(item_id) do
    from(e in ActivityEvent,
      where: e.secrets_vault_item_id == ^item_id and e.action == "copy",
      order_by: [desc: e.inserted_at, desc: e.id],
      limit: 1,
      select: e.inserted_at
    )
    |> Repo.one()
  end

  def latest_copy_at(_), do: nil

  def device_label do
    host =
      case :inet.gethostname() do
        {:ok, name} -> name |> to_string() |> String.downcase()
        _ -> "local-device"
      end

    label =
      host
      |> String.split(".", parts: 2)
      |> List.first()
      |> case do
        nil -> "local-device"
        "" -> "local-device"
        part -> part
      end

    "#{label} · local"
  end

  def update_summary(changed_fields, kind) when is_list(changed_fields) do
    fields = Enum.uniq(changed_fields)

    cond do
      "body" in fields ->
        body_update_summary(kind)

      length(fields) == 1 ->
        single_field_summary(hd(fields))

      length(fields) == 2 ->
        fields
        |> Enum.map(&single_field_summary/1)
        |> Enum.join(" · ")

      true ->
        "Updated entry"
    end
  end

  def update_summary(_, _), do: "Updated entry"

  def changed_fields(previous, next) when is_map(previous) and is_map(next) do
    title_changed = Map.get(previous, :title) != Map.get(next, :title)
    kind_changed = Map.get(previous, :kind) != Map.get(next, :kind)

    folder_changed =
      Map.get(previous, :secrets_vault_folder_id) != Map.get(next, :secrets_vault_folder_id)

    body_changed = Map.get(previous, :body, "") != Map.get(next, :body, "")

    prev_fm = Map.get(previous, :frontmatter, %{}) || %{}
    next_fm = Map.get(next, :frontmatter, %{}) || %{}

    fm_keys =
      MapSet.union(MapSet.new(Map.keys(prev_fm)), MapSet.new(Map.keys(next_fm)))
      |> Enum.filter(fn key -> Map.get(prev_fm, key, "") != Map.get(next_fm, key, "") end)

    []
    |> then(fn acc -> if title_changed, do: ["title" | acc], else: acc end)
    |> then(fn acc -> if kind_changed, do: ["kind" | acc], else: acc end)
    |> then(fn acc -> if folder_changed, do: ["folder" | acc], else: acc end)
    |> then(fn acc -> if body_changed, do: ["body" | acc], else: acc end)
    |> Kernel.++(fm_keys)
    |> Enum.reverse()
  end

  def changed_fields(_, _), do: []

  def display_rows(%Item{} = item, events) when is_list(events) do
    rows = Enum.map(events, &event_to_row/1)

    cond do
      rows == [] ->
        synthesize_backfill(item)

      Enum.any?(rows, &(&1.action == "create")) ->
        rows

      true ->
        rows ++ [synthetic_create_row(item)]
    end
  end

  def display_rows(_, _), do: []

  def ensure_create_event(item_id) when is_integer(item_id) do
    if has_create_event?(item_id) do
      :ok
    else
      case Repo.get(Item, item_id) do
        %Item{} = item -> insert_create_event(item)
        _ -> :ok
      end
    end
  end

  def ensure_create_event(_), do: :ok

  defp has_create_event?(item_id) do
    from(e in ActivityEvent,
      where: e.secrets_vault_item_id == ^item_id and e.action == "create",
      select: 1,
      limit: 1
    )
    |> Repo.exists?()
  end

  defp insert_create_event(%Item{} = item) do
    attrs = %{
      secrets_vault_item_id: item.id,
      action: "create",
      summary: "Created entry",
      device_label: device_label(),
      metadata: %{"backfilled" => true}
    }

    changeset =
      %ActivityEvent{}
      |> ActivityEvent.changeset(attrs)
      |> Ecto.Changeset.put_change(:inserted_at, utc_datetime(item.inserted_at))

    case Repo.insert(changeset) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp utc_datetime(%DateTime{} = dt), do: DateTime.truncate(dt, :second)

  defp utc_datetime(%NaiveDateTime{} = dt) do
    dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.truncate(:second)
  end

  defp utc_datetime(_), do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp synthesize_backfill(%Item{} = item) do
    created = synthetic_create_row(item)

    if meaningful_update?(item) do
      [
        %{
          id: "backfill-update-#{item.id}",
          action: "update",
          summary: "Updated entry",
          device_label: device_label(),
          inserted_at: item.updated_at
        },
        created
      ]
    else
      [created]
    end
  end

  defp synthetic_create_row(%Item{} = item) do
    %{
      id: "backfill-create-#{item.id}",
      action: "create",
      summary: "Created entry",
      device_label: device_label(),
      inserted_at: item.inserted_at
    }
  end

  defp meaningful_update?(%Item{
         inserted_at: %DateTime{} = created,
         updated_at: %DateTime{} = updated
       }) do
    DateTime.diff(updated, created, :second) >= 2
  end

  defp meaningful_update?(%Item{
         inserted_at: %NaiveDateTime{} = created,
         updated_at: %NaiveDateTime{} = updated
       }) do
    NaiveDateTime.diff(updated, created, :second) >= 2
  end

  defp meaningful_update?(_), do: false

  defp event_to_row(%ActivityEvent{} = event) do
    %{
      id: event.id,
      action: event.action,
      summary: event.summary,
      device_label: event.device_label,
      inserted_at: event.inserted_at
    }
  end

  defp body_update_summary("password"), do: "Rotated password"
  defp body_update_summary("api_key"), do: "Updated token"
  defp body_update_summary("ssh_key"), do: "Updated passphrase"
  defp body_update_summary("secure_note"), do: "Updated note"
  defp body_update_summary(_), do: "Updated secret"

  defp single_field_summary("title"), do: "Renamed entry"
  defp single_field_summary("kind"), do: "Changed type"
  defp single_field_summary("folder"), do: "Moved folder"
  defp single_field_summary("body"), do: "Updated secret"

  defp single_field_summary(field) when is_binary(field) do
    Map.get(@frontmatter_labels, field, "Updated entry")
  end

  defp single_field_summary(_), do: "Updated entry"
end
