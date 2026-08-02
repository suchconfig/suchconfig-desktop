defmodule SuchConfigDesktop.Vault.Crdt do
  @moduledoc """
  NIF bridge to the `suchconfig_vault_core` Rust crate (Loro-backed CRDT).

  The NIF is **opt-in**: when it fails to load (missing Rust toolchain, unsupported
  platform, feature flag off) every public function in this module returns
  `{:error, :nif_unavailable}` without raising. Callers MUST check
  `available?/0` or handle the error tuple.
  """

  use Rustler,
    otp_app: :suchconfig_desktop,
    crate: "vault_crdt"

  @type kind ::
          :env_note
          | :generic_note
          | :prompt_template
          | :guideline
          | :api_spec
          | :security_policy
          | :security_manifest
          | :password
          | :api_key
          | :ssh_key
          | :secure_note

  @type snapshot :: binary()
  @type update_bytes :: binary()
  @type merge_summary :: %{
          required(:ops_applied) => non_neg_integer(),
          required(:peers) => [non_neg_integer()],
          required(:new_snapshot_hash) => String.t(),
          required(:local_frontier) => String.t(),
          required(:remote_frontier) => String.t()
        }

  @type error_reason ::
          :nif_unavailable
          | :unknown_kind
          | :malformed
          | :byte_cap
          | :kind_mismatch
          | :snapshot_decode
          | :delta_decode
          | :unsupported_version
          | :loro

  @allowed_kinds ~w(
    env_note generic_note prompt_template guideline api_spec security_policy security_manifest
    password api_key ssh_key secure_note
  )

  @kind_atoms [
    :env_note,
    :generic_note,
    :prompt_template,
    :guideline,
    :api_spec,
    :security_policy,
    :security_manifest,
    :password,
    :api_key,
    :ssh_key,
    :secure_note
  ]

  @doc """
  Returns `true` when the Rustler NIF is loaded and usable.
  """
  @spec available?() :: boolean()
  def available? do
    case nif_new_doc("generic_note") do
      {:ok, _snap} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  @doc """
  Creates a new empty CRDT snapshot for the given kind.
  """
  @spec new_doc(kind() | String.t()) :: {:ok, snapshot()} | {:error, error_reason(), String.t()}
  def new_doc(kind) do
    with {:ok, kind_str} <- coerce_kind(kind) do
      case nif_new_doc(kind_str) do
        {:ok, snap} -> {:ok, snap}
        {:error, reason, message} -> {:error, reason, message}
      end
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec decode_kind(snapshot()) :: {:ok, kind()} | {:error, error_reason(), String.t()}
  def decode_kind(snapshot) when is_binary(snapshot) do
    case nif_decode_snapshot(snapshot) do
      {:ok, kind_str} ->
        case coerce_kind(kind_str) do
          {:ok, _} ->
            case kind_string_to_atom(kind_str) do
              nil -> {:error, :unknown_kind, "unknown kind: #{kind_str}"}
              atom -> {:ok, atom}
            end

          {:error, reason, message} ->
            {:error, reason, message}
        end

      {:error, reason, message} ->
        {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec body(snapshot()) :: {:ok, String.t()} | {:error, error_reason(), String.t()}
  def body(snapshot) when is_binary(snapshot) do
    case nif_extract_body(snapshot) do
      {:ok, body} -> {:ok, body}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec set_body(snapshot(), String.t()) ::
          {:ok, snapshot()} | {:error, error_reason(), String.t()}
  def set_body(snapshot, body) when is_binary(snapshot) and is_binary(body) do
    case nif_set_body(snapshot, body) do
      {:ok, new_snap} -> {:ok, new_snap}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec apply_update(snapshot(), update_bytes()) ::
          {:ok, snapshot(), merge_summary()} | {:error, error_reason(), String.t()}
  def apply_update(snapshot, update) when is_binary(snapshot) and is_binary(update) do
    case nif_apply_update(snapshot, update) do
      {:ok, new_snap, summary_json} ->
        summary = parse_summary(summary_json)
        {:ok, new_snap, summary}

      {:error, reason, message} ->
        {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec diff_from(snapshot(), snapshot()) ::
          {:ok, update_bytes()} | {:error, error_reason(), String.t()}
  def diff_from(current_snapshot, peer_snapshot)
      when is_binary(current_snapshot) and is_binary(peer_snapshot) do
    case nif_diff_from(current_snapshot, peer_snapshot) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec snapshot_hash(snapshot()) :: {:ok, String.t()} | {:error, error_reason(), String.t()}
  def snapshot_hash(snapshot) when is_binary(snapshot) do
    case nif_snapshot_hash(snapshot) do
      {:ok, hash} -> {:ok, hash}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  defp coerce_kind(kind) when is_atom(kind), do: coerce_kind(Atom.to_string(kind))

  defp coerce_kind(kind) when is_binary(kind) do
    if kind in @allowed_kinds do
      {:ok, kind}
    else
      {:error, :unknown_kind, "unknown kind: #{kind}"}
    end
  end

  defp coerce_kind(_), do: {:error, :unknown_kind, "kind must be atom or string"}

  defp kind_string_to_atom(kind_str) when is_binary(kind_str) do
    Enum.find(@kind_atoms, fn atom -> Atom.to_string(atom) == kind_str end)
  end

  defp parse_summary(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, map} ->
        %{
          ops_applied: Map.get(map, "ops_applied", 0),
          peers: Map.get(map, "peers", []),
          new_snapshot_hash: Map.get(map, "new_snapshot_hash", ""),
          local_frontier: Map.get(map, "local_frontier", ""),
          remote_frontier: Map.get(map, "remote_frontier", "")
        }

      _ ->
        %{
          ops_applied: 0,
          peers: [],
          new_snapshot_hash: "",
          local_frontier: "",
          remote_frontier: ""
        }
    end
  end

  defp nif_new_doc(_kind), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_decode_snapshot(_snapshot), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_extract_body(_snapshot), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_set_body(_snapshot, _body), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_apply_update(_snapshot, _update), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_diff_from(_current, _peer), do: :erlang.nif_error(:nif_not_loaded)
  defp nif_snapshot_hash(_snapshot), do: :erlang.nif_error(:nif_not_loaded)

  @spec set_frontmatter_string(snapshot(), String.t(), String.t()) ::
          {:ok, snapshot()} | {:error, error_reason(), String.t()}
  def set_frontmatter_string(snapshot, key, value)
      when is_binary(snapshot) and is_binary(key) and is_binary(value) do
    case nif_set_frontmatter_string(snapshot, key, value) do
      {:ok, new_snap} -> {:ok, new_snap}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec frontmatter_string(snapshot(), String.t()) ::
          {:ok, String.t() | nil} | {:error, error_reason(), String.t()}
  def frontmatter_string(snapshot, key) when is_binary(snapshot) and is_binary(key) do
    case nif_frontmatter_string(snapshot, key) do
      {:ok, nil} -> {:ok, nil}
      {:ok, value} when is_binary(value) -> {:ok, value}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  @spec apply_frontmatter(snapshot(), %{String.t() => String.t()}) ::
          {:ok, snapshot()} | {:error, error_reason(), String.t()}
  def apply_frontmatter(snapshot, pairs) when is_binary(snapshot) and is_map(pairs) do
    Enum.reduce_while(pairs, {:ok, snapshot}, fn {k, v}, {:ok, snap} ->
      case set_frontmatter_string(snap, k, v) do
        {:ok, next} -> {:cont, {:ok, next}}
        {:error, _, _} = err -> {:halt, err}
      end
    end)
  end

  defp nif_set_frontmatter_string(_snapshot, _key, _value),
    do: :erlang.nif_error(:nif_not_loaded)

  defp nif_frontmatter_string(_snapshot, _key), do: :erlang.nif_error(:nif_not_loaded)

  @spec change_count(snapshot()) ::
          {:ok, non_neg_integer()} | {:error, error_reason(), String.t()}
  def change_count(snapshot) when is_binary(snapshot) do
    case nif_change_count(snapshot) do
      {:ok, n} -> {:ok, n}
      {:error, reason, message} -> {:error, reason, message}
    end
  rescue
    _ -> {:error, :nif_unavailable, "NIF not loaded"}
  end

  defp nif_change_count(_snapshot), do: :erlang.nif_error(:nif_not_loaded)
end
