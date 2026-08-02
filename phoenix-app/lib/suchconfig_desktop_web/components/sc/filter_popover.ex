defmodule SuchConfigDesktopWeb.Sc.FilterPopover do
  @moduledoc false

  use Phoenix.Component

  import SuchConfigDesktopWeb.Sc.Icon

  @type_options [
    %{id: "login", label: "Logins", color: "var(--accent)"},
    %{id: "api", label: "API keys", color: "var(--moss)"},
    %{id: "ssh", label: "SSH", color: "var(--plum)"},
    %{id: "note", label: "Notes", color: "var(--ink-2)"}
  ]

  attr :id, :string, default: "filter-popover"
  attr :open, :boolean, default: false
  attr :active_count, :integer, default: 0
  attr :panel_query, :string, default: ""
  attr :selected_types, :list, default: []
  attr :selected_tags, :list, default: []
  attr :type_options, :list, default: []
  attr :tag_options, :list, default: []
  attr :toggle_event, :string, default: "toggle_filter_panel"
  attr :panel_search_event, :string, default: "filter_panel_search"
  attr :toggle_type_event, :string, default: "toggle_filter_type"
  attr :toggle_tag_event, :string, default: "toggle_filter_tag"
  attr :clear_event, :string, default: "clear_filters"

  def filter_toolbar(assigns) do
    ~H"""
    <.filter_button {assigns} />
    <.filter_panel {panel_assigns(assigns)} open={@open} />
    """
  end

  attr :id, :string, default: "filter-popover"
  attr :open, :boolean, default: false
  attr :active_count, :integer, default: 0
  attr :toggle_event, :string, default: "toggle_filter_panel"

  def filter_button(assigns) do
    ~H"""
    <div class="filter-anchor" id={@id}>
      <button
        type="button"
        phx-click={@toggle_event}
        id={"#{@id}-button"}
        class={[
          "btn xs icon-only filter-btn",
          @active_count > 0 && "has-filters",
          @open && "open"
        ]}
        title="Filter"
        aria-expanded={to_string(@open)}
        aria-haspopup="dialog"
        aria-controls={"#{@id}-panel"}
      >
        <.icon name="filter" size={13} />
        <span :if={@active_count > 0} class="filter-btn-badge">{@active_count}</span>
      </button>
    </div>
    """
  end

  def panel_assigns(assigns) do
    type_rows = visible_type_rows(assigns)
    tag_rows = visible_tag_rows(assigns)

    %{
      id: Map.get(assigns, :id, "filter-popover") <> "-panel",
      panel_query: Map.get(assigns, :panel_query, ""),
      selected_types: Map.get(assigns, :selected_types, []),
      selected_tags: Map.get(assigns, :selected_tags, []),
      type_rows: type_rows,
      tag_rows: tag_rows,
      show_empty: type_rows == [] and tag_rows == [],
      active_count: Map.get(assigns, :active_count, 0),
      panel_search_event: Map.get(assigns, :panel_search_event, "filter_panel_search"),
      toggle_type_event: Map.get(assigns, :toggle_type_event, "toggle_filter_type"),
      toggle_tag_event: Map.get(assigns, :toggle_tag_event, "toggle_filter_tag"),
      clear_event: Map.get(assigns, :clear_event, "clear_filters")
    }
  end

  attr :id, :string, required: true
  attr :panel_query, :string, default: ""
  attr :selected_types, :list, default: []
  attr :selected_tags, :list, default: []
  attr :type_rows, :list, default: []
  attr :tag_rows, :list, default: []
  attr :show_empty, :boolean, default: false
  attr :active_count, :integer, default: 0
  attr :panel_search_event, :string, default: "filter_panel_search"
  attr :toggle_type_event, :string, default: "toggle_filter_type"
  attr :toggle_tag_event, :string, default: "toggle_filter_tag"
  attr :clear_event, :string, default: "clear_filters"
  attr :open, :boolean, default: false

  def filter_panel(assigns) do
    ~H"""
    <div
      class={["filter-pop", !@open && "filter-pop--closed"]}
      id={@id}
      role="dialog"
      aria-label="Filter"
      aria-hidden={to_string(!@open)}
    >
      <.form
        for={%{}}
        phx-change={@panel_search_event}
        id={"#{@id}-search-form"}
        class="filter-pop-search"
      >
        <.icon name="search" size={13} />
        <input
          type="search"
          name="query"
          value={@panel_query}
          placeholder="Filter…"
          id={"#{@id}-search-input"}
        />
      </.form>

      <div :if={@type_rows != []} class="filter-pop-section">
        <div class="filter-pop-label">Type</div>
        <button
          :for={type <- @type_rows}
          type="button"
          phx-click={@toggle_type_event}
          phx-value-type={type.id}
          id={"#{@id}-type-#{type.id}"}
          class={["filter-pop-row", type.id in @selected_types && "on"]}
        >
          <span class="filter-pop-check">
            <.icon :if={type.id in @selected_types} name="check" size={12} />
          </span>
          <span class="filter-pop-dot" style={"background: #{type.color}"} />
          <span class="filter-pop-text">{type.label}</span>
          <span class="filter-pop-count">{type.count}</span>
        </button>
      </div>

      <div :if={@tag_rows != []} class="filter-pop-section">
        <div class="filter-pop-label">Tags</div>
        <div class="filter-pop-scroll">
          <button
            :for={tag <- @tag_rows}
            type="button"
            phx-click={@toggle_tag_event}
            phx-value-tag={tag.tag}
            id={"#{@id}-tag-#{tag.slug}"}
            class={["filter-pop-row", tag.tag in @selected_tags && "on"]}
          >
            <span class="filter-pop-check">
              <.icon :if={tag.tag in @selected_tags} name="check" size={12} />
            </span>
            <span class="filter-pop-hash">#</span>
            <span class="filter-pop-text">{tag.tag}</span>
            <span class="filter-pop-count">{tag.count}</span>
          </button>
        </div>
      </div>

      <div :if={@show_empty} class="filter-pop-empty">No matches</div>

      <div class="filter-pop-foot">
        <span class="faint" style="font-size: 11px">
          {if @active_count == 0, do: "No filters", else: "#{@active_count} active"}
        </span>
        <button
          type="button"
          phx-click={@clear_event}
          class="btn xs ghost"
          disabled={@active_count == 0}
          id={"#{@id}-clear"}
        >
          Clear all
        </button>
      </div>
    </div>
    """
  end

  attr :selected_types, :list, default: []
  attr :selected_tags, :list, default: []
  attr :toggle_type_event, :string, default: "toggle_filter_type"
  attr :toggle_tag_event, :string, default: "toggle_filter_tag"
  attr :clear_event, :string, default: "clear_filters"

  def filter_chips(assigns) do
    ~H"""
    <div :if={@selected_types != [] or @selected_tags != []} class="filter-chips" id="filter-chips">
      <button
        :for={type_id <- @selected_types}
        type="button"
        phx-click={@toggle_type_event}
        phx-value-type={type_id}
        class="filter-chip"
      >
        <span class="filter-pop-dot" style={"background: #{type_color(type_id)}"} />
        {type_label(type_id)}
        <.icon name="x" size={10} />
      </button>
      <button
        :for={tag <- @selected_tags}
        type="button"
        phx-click={@toggle_tag_event}
        phx-value-tag={tag}
        class="filter-chip"
      >
        <span class="filter-pop-hash">#</span>{tag}
        <.icon name="x" size={10} />
      </button>
      <button type="button" phx-click={@clear_event} class="filter-chip clear">Clear</button>
    </div>
    """
  end

  def type_options, do: @type_options

  def type_label(type_id) do
    case Enum.find(@type_options, &(&1.id == type_id)) do
      %{label: label} -> label
      _ -> type_id
    end
  end

  def type_color(type_id) do
    case Enum.find(@type_options, &(&1.id == type_id)) do
      %{color: color} -> color
      _ -> "var(--ink-2)"
    end
  end

  defp visible_type_rows(assigns) do
    ql = panel_query_lower(Map.get(assigns, :panel_query, ""))

    Enum.filter(Map.get(assigns, :type_options, []), fn type ->
      ql == "" or String.contains?(String.downcase(type.label), ql)
    end)
  end

  defp visible_tag_rows(assigns) do
    ql = panel_query_lower(Map.get(assigns, :panel_query, ""))

    Enum.filter(Map.get(assigns, :tag_options, []), fn tag ->
      ql == "" or String.contains?(String.downcase(tag.tag), ql)
    end)
  end

  defp panel_query_lower(query) when is_binary(query), do: String.trim(query) |> String.downcase()
  defp panel_query_lower(_), do: ""
end
