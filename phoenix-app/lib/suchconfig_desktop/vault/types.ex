defmodule SuchConfigDesktop.Vault.Types do
  @moduledoc """
  Boundary type coercion for the Vault.

  Every public function in `SuchConfigDesktop.Vault.*` runs raw inputs
  (HEEx form params, JSON from the CRDT NIF, Tauri command payloads) through
  this module at the entry point. The goal is a single place to enforce
  allow-lists for atoms, normalize camelCase/snake_case JSON from the Rust
  side, and map legacy `ProjectVault` conflict strategies onto the new model.

  The shapes here are intentionally `Ash.Type.Atom`-compatible: `constraints/1`
  returns the same keyword list Ash would consume, so when `:ash` lands in
  `mix.exs` the Vault resources can adopt these constraints verbatim.
  """

  @kinds [
    :env_note,
    :generic_note,
    :prompt_template,
    :guideline,
    :api_spec,
    :security_policy,
    :security_manifest
  ]
  @kind_strings Enum.map(@kinds, &Atom.to_string/1)

  @security_modes [:global_passkey, :per_note_password]
  @security_mode_strings Enum.map(@security_modes, &Atom.to_string/1)

  @conflict_strategies [:duplicate, :keep_existing, :replace]
  @conflict_strategy_strings Enum.map(@conflict_strategies, &Atom.to_string/1)

  @type kind ::
          :env_note
          | :generic_note
          | :prompt_template
          | :guideline
          | :api_spec
          | :security_policy
          | :security_manifest
  @type security_mode :: :global_passkey | :per_note_password
  @type conflict_strategy :: :duplicate | :keep_existing | :replace

  @spec allowed_kinds() :: [kind()]
  def allowed_kinds, do: @kinds

  @spec allowed_kind_strings() :: [String.t()]
  def allowed_kind_strings, do: @kind_strings

  @spec allowed_security_modes() :: [security_mode()]
  def allowed_security_modes, do: @security_modes

  @spec allowed_conflict_strategies() :: [conflict_strategy()]
  def allowed_conflict_strategies, do: @conflict_strategies

  @spec constraints(atom()) :: keyword()
  def constraints(:kind), do: [one_of: @kinds]
  def constraints(:security_mode), do: [one_of: @security_modes]
  def constraints(:conflict_strategy), do: [one_of: @conflict_strategies]
  def constraints(_other), do: []

  @spec cast_kind(term()) :: {:ok, kind()} | {:error, :unknown_kind}
  def cast_kind(value) when value in @kinds, do: {:ok, value}

  def cast_kind(value) when is_binary(value) do
    if value in @kind_strings do
      {:ok, safe_atom_from_allowlist(value, @kinds)}
    else
      {:error, :unknown_kind}
    end
  end

  def cast_kind(_), do: {:error, :unknown_kind}

  @spec cast_security_mode(term()) :: {:ok, security_mode()} | {:error, :unknown_security_mode}
  def cast_security_mode(value) when value in @security_modes, do: {:ok, value}

  def cast_security_mode(value) when is_binary(value) do
    if value in @security_mode_strings do
      {:ok, safe_atom_from_allowlist(value, @security_modes)}
    else
      {:error, :unknown_security_mode}
    end
  end

  def cast_security_mode(_), do: {:error, :unknown_security_mode}

  @spec cast_conflict_strategy(term()) :: {:ok, conflict_strategy()}
  def cast_conflict_strategy(value) when value in @conflict_strategies, do: {:ok, value}

  def cast_conflict_strategy(value) when is_binary(value) do
    if value in @conflict_strategy_strings do
      {:ok, safe_atom_from_allowlist(value, @conflict_strategies)}
    else
      {:ok, :duplicate}
    end
  end

  def cast_conflict_strategy(_), do: {:ok, :duplicate}

  @spec cast_boolean(term()) :: {:ok, boolean()} | {:error, :invalid_boolean}
  def cast_boolean(true), do: {:ok, true}
  def cast_boolean(false), do: {:ok, false}
  def cast_boolean("true"), do: {:ok, true}
  def cast_boolean("false"), do: {:ok, false}
  def cast_boolean("on"), do: {:ok, true}
  def cast_boolean("off"), do: {:ok, false}
  def cast_boolean("1"), do: {:ok, true}
  def cast_boolean("0"), do: {:ok, false}
  def cast_boolean(_), do: {:error, :invalid_boolean}

  @spec coerce_attrs(map()) ::
          {:ok,
           %{
             optional(:kind) => kind(),
             optional(:security_mode) => security_mode(),
             optional(:title) => String.t(),
             optional(:description) => String.t() | nil,
             optional(:tags) => String.t() | nil,
             optional(:project_folder_id) => integer() | nil
           }}
          | {:error, :unknown_kind | :unknown_security_mode | :missing_title}
  def coerce_attrs(params) when is_map(params) do
    params = stringify_keys(params)

    with {:ok, kind} <- maybe_cast_kind(params),
         {:ok, security_mode} <- maybe_cast_security_mode(params),
         {:ok, title} <- require_title(params) do
      attrs =
        %{}
        |> put_if(kind, :kind)
        |> put_if(security_mode, :security_mode)
        |> Map.put(:title, title)
        |> Map.put(:description, nil_if_blank(Map.get(params, "description")))
        |> Map.put(:tags, nil_if_blank(Map.get(params, "tags")))
        |> put_project_folder_id(params)

      {:ok, attrs}
    end
  end

  @spec normalize_merge_summary(map()) :: map()
  def normalize_merge_summary(map) when is_map(map) do
    %{
      ops_applied: get_first(map, ["ops_applied", "opsApplied"], 0),
      peers: get_first(map, ["peers"], []),
      new_snapshot_hash: get_first(map, ["new_snapshot_hash", "newSnapshotHash"], ""),
      local_frontier: get_first(map, ["local_frontier", "localFrontier"], ""),
      remote_frontier: get_first(map, ["remote_frontier", "remoteFrontier"], "")
    }
  end

  defp safe_atom_from_allowlist(string, allowed_atoms) do
    Enum.find(allowed_atoms, fn atom -> Atom.to_string(atom) == string end)
  end

  defp stringify_keys(map) do
    Enum.into(map, %{}, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp maybe_cast_kind(params) do
    case Map.get(params, "kind") do
      nil -> {:ok, nil}
      value -> cast_kind(value)
    end
  end

  defp maybe_cast_security_mode(params) do
    case Map.get(params, "security_mode") do
      nil -> {:ok, nil}
      value -> cast_security_mode(value)
    end
  end

  defp require_title(params) do
    case Map.get(params, "title") do
      nil ->
        {:error, :missing_title}

      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, :missing_title}, else: {:ok, trimmed}

      _ ->
        {:error, :missing_title}
    end
  end

  defp put_if(map, nil, _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)

  defp nil_if_blank(nil), do: nil
  defp nil_if_blank(""), do: nil

  defp nil_if_blank(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp nil_if_blank(value), do: value

  defp put_project_folder_id(attrs, params) do
    case Map.get(params, "project_folder_id") do
      nil ->
        attrs

      id when is_integer(id) ->
        Map.put(attrs, :project_folder_id, id)

      id when is_binary(id) ->
        case Integer.parse(id) do
          {parsed, ""} -> Map.put(attrs, :project_folder_id, parsed)
          _ -> attrs
        end

      _ ->
        attrs
    end
  end

  defp get_first(map, keys, default) do
    Enum.find_value(keys, default, fn key ->
      case Map.get(map, key) do
        nil -> nil
        value -> value
      end
    end)
  end
end
