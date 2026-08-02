defmodule SuchConfigDesktopWeb.Components.ProjectVault.MergeAuditPanel do
  use Phoenix.Component

  attr :events, :list, required: true

  def merge_audit_panel(assigns) do
    ~H"""
    <div id="vault-merge-audit-panel" class="card">
      <h4>Recent vault activity</h4>
      <p class="muted" style="margin-bottom: 14px; font-size: 12px">
        Export and import events on this device. No vault content is logged here.
      </p>
      <div
        :if={@events != []}
        class="audit"
        style="max-height: min(60vh, 36rem); overflow-y: auto"
      >
        <div
          :for={event <- @events}
          class={["audit-row", audit_row_class(event.operation)]}
        >
          <span class="blip" />
          <span class="when">{format_inserted_at(event.inserted_at)}</span>
          <span class="what">{format_operation(event.operation)}</span>
          <span class="where">{format_metadata(event.operation, event.metadata)}</span>
        </div>
      </div>
      <p :if={@events == []} class="faint" style="margin: 0; font-size: 12px">
        No export or import activity yet.
      </p>
    </div>
    """
  end

  defp audit_row_class("export"), do: "copy"
  defp audit_row_class("import"), do: "create"
  defp audit_row_class("crdt_merge"), do: "edit"
  defp audit_row_class("export_unpacked"), do: "copy"
  defp audit_row_class(_), do: nil

  defp format_operation("export"), do: "Secure archive exported"
  defp format_operation("import"), do: "Secure archive imported"
  defp format_operation("crdt_merge"), do: "Vault items merged (CRDT)"
  defp format_operation("export_unpacked"), do: "Archive unpacked"

  defp format_operation(other) when is_binary(other),
    do: other |> String.replace("_", " ") |> String.capitalize()

  defp format_operation(_), do: "Activity"

  defp format_inserted_at(%DateTime{} = dt) do
    Calendar.strftime(dt, "%Y-%m-%d %H:%M UTC")
  end

  defp format_inserted_at(_), do: ""

  defp format_metadata(operation, metadata) when is_map(metadata) do
    parts =
      case operation do
        "export" ->
          [
            format_kv("Format", meta_get(metadata, "format")),
            format_kv("Version", meta_get_int(metadata, "format_version")),
            format_kv("Folders", meta_get_int(metadata, "folder_count"))
          ]

        "import" ->
          routing = meta_get_map(metadata, "folder_routing_summary")

          [
            format_kv("Format", meta_get(metadata, "format")),
            format_kv("Version", meta_get_int(metadata, "format_version")),
            format_kv("Strategy", meta_get(metadata, "conflict_strategy")),
            format_kv("Folders touched", meta_get_int(metadata, "imported_folder_count")),
            if(routing,
              do: format_kv("Notes", meta_get_int(routing, "notes_imported")),
              else: nil
            ),
            if(routing,
              do: format_kv("Vault items", meta_get_int(routing, "vault_items_imported")),
              else: nil
            ),
            if(routing,
              do: format_kv("Vault merges", meta_get_int(routing, "vault_items_merged")),
              else: nil
            )
          ]

        "crdt_merge" ->
          [
            format_kv("Summary", meta_get(metadata, "summary")),
            format_kv("Items", meta_get_int(metadata, "items_merged"))
          ]

        _ ->
          []
      end
      |> Enum.reject(&(&1 == nil or &1 == ""))

    if parts == [], do: "—", else: Enum.join(parts, " · ")
  end

  defp format_metadata(_, _), do: "—"

  defp format_kv(_label, nil), do: nil
  defp format_kv(_label, ""), do: nil
  defp format_kv(label, value), do: "#{label} #{value}"

  defp pick(m, key) when is_binary(key) do
    case Map.get(m, key) do
      nil ->
        case safe_atom(key) do
          nil -> nil
          a -> Map.get(m, a)
        end

      v ->
        v
    end
  end

  defp safe_atom(key) do
    try do
      String.to_existing_atom(key)
    rescue
      ArgumentError -> nil
    end
  end

  defp meta_get(m, key) do
    case pick(m, key) do
      nil -> nil
      v when is_binary(v) -> v
      v when is_integer(v) -> Integer.to_string(v)
      v when is_atom(v) -> Atom.to_string(v)
      _ -> nil
    end
  end

  defp meta_get_int(m, key) do
    case pick(m, key) do
      v when is_integer(v) ->
        Integer.to_string(v)

      v when is_binary(v) ->
        case Integer.parse(v) do
          {i, _} -> Integer.to_string(i)
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp meta_get_map(m, key) do
    case pick(m, key) do
      %{} = inner -> inner
      _ -> nil
    end
  end
end
