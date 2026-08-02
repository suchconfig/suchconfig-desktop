defmodule SuchConfigDesktop.Vault.TypesTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.Vault.Types

  describe "cast_kind/1 — atoms vs strings, allow-list only" do
    test "accepts allow-listed strings and returns atoms" do
      for {input, expected} <- [
            {"env_note", :env_note},
            {"generic_note", :generic_note},
            {"prompt_template", :prompt_template},
            {"guideline", :guideline},
            {"api_spec", :api_spec},
            {"security_policy", :security_policy}
          ] do
        assert {:ok, ^expected} = Types.cast_kind(input)
      end
    end

    test "accepts allow-listed atoms idempotently" do
      for kind <- Types.allowed_kinds() do
        assert {:ok, ^kind} = Types.cast_kind(kind)
      end
    end

    test "rejects arbitrary strings without creating new atoms" do
      assert {:error, :unknown_kind} =
               Types.cast_kind("malicious_kind_#{:rand.uniform(1_000_000)}")

      refute function_exported?(:not_a_real_mod, :dummy, 0)
    end

    test "rejects nil, integers, and maps" do
      for bad <- [nil, 42, %{}, [:list], :random_atom] do
        assert {:error, :unknown_kind} = Types.cast_kind(bad)
      end
    end
  end

  describe "cast_security_mode/1" do
    test "accepts allow-listed modes" do
      assert {:ok, :global_passkey} = Types.cast_security_mode("global_passkey")
      assert {:ok, :per_note_password} = Types.cast_security_mode("per_note_password")
      assert {:ok, :global_passkey} = Types.cast_security_mode(:global_passkey)
    end

    test "rejects unknown modes" do
      assert {:error, :unknown_security_mode} = Types.cast_security_mode("no_security")
    end
  end

  describe "cast_conflict_strategy/1 — shared with ProjectVault legacy path" do
    test "normalizes the three legacy strings" do
      assert {:ok, :duplicate} = Types.cast_conflict_strategy("duplicate")
      assert {:ok, :keep_existing} = Types.cast_conflict_strategy("keep_existing")
      assert {:ok, :replace} = Types.cast_conflict_strategy("replace")
    end

    test "accepts atoms as input" do
      assert {:ok, :replace} = Types.cast_conflict_strategy(:replace)
    end

    test "defaults unknown values to :duplicate for backward compat" do
      assert {:ok, :duplicate} = Types.cast_conflict_strategy("???")
      assert {:ok, :duplicate} = Types.cast_conflict_strategy(nil)
    end
  end

  describe "cast_boolean/1" do
    test "coerces HEEx string booleans" do
      assert Types.cast_boolean("true") == {:ok, true}
      assert Types.cast_boolean("false") == {:ok, false}
      assert Types.cast_boolean("on") == {:ok, true}
      assert Types.cast_boolean("off") == {:ok, false}
      assert Types.cast_boolean(true) == {:ok, true}
      assert Types.cast_boolean(false) == {:ok, false}
    end

    test "rejects other values" do
      assert Types.cast_boolean("maybe") == {:error, :invalid_boolean}
      assert Types.cast_boolean(nil) == {:error, :invalid_boolean}
    end
  end

  describe "coerce_attrs/1 — form params to VaultItem attrs" do
    test "maps kind+security_mode strings and strips empty strings to nil" do
      input = %{
        "kind" => "prompt_template",
        "security_mode" => "global_passkey",
        "title" => "Pirate mode",
        "description" => "",
        "tags" => ""
      }

      assert {:ok, attrs} = Types.coerce_attrs(input)
      assert attrs.kind == :prompt_template
      assert attrs.security_mode == :global_passkey
      assert attrs.title == "Pirate mode"
      assert attrs.description == nil
      assert attrs.tags == nil
    end

    test "accepts atom-keyed maps identically" do
      assert {:ok, attrs} =
               Types.coerce_attrs(%{
                 kind: :guideline,
                 security_mode: :global_passkey,
                 title: "OAuth policy"
               })

      assert attrs.kind == :guideline
      assert attrs.title == "OAuth policy"
    end

    test "returns error for unknown kind without partial attrs" do
      assert {:error, :unknown_kind} =
               Types.coerce_attrs(%{"kind" => "not_a_kind", "title" => "x"})
    end

    test "title is required when creating new items (empty -> error)" do
      assert {:error, :missing_title} = Types.coerce_attrs(%{"kind" => "generic_note"})

      assert {:error, :missing_title} =
               Types.coerce_attrs(%{"kind" => "generic_note", "title" => "   "})
    end
  end

  describe "Ash parity: allowed_kinds/0 exposes a stable allow-list" do
    test "list is a flat list of atoms and matches the code-side enum in both kind + string form" do
      kinds = Types.allowed_kinds()
      assert is_list(kinds)
      assert Enum.all?(kinds, &is_atom/1)
      assert :security_manifest in kinds
      assert length(kinds) == 7

      strings = Types.allowed_kind_strings()
      assert Enum.sort(strings) == Enum.sort(Enum.map(kinds, &Atom.to_string/1))
    end

    test "constraints/1 returns an `Ash.Type.Atom`-compatible keyword list" do
      constraints = Types.constraints(:kind)
      assert Keyword.get(constraints, :one_of) == Types.allowed_kinds()
    end
  end

  describe "normalize_merge_summary/1 — Rust JSON -> Elixir atom keys" do
    test "camelCase/snake_case keys both flatten to snake_case atoms" do
      snake = %{
        "ops_applied" => 3,
        "peers" => [1, 2],
        "new_snapshot_hash" => "abc",
        "local_frontier" => "lf",
        "remote_frontier" => "rf"
      }

      camel = %{
        "opsApplied" => 3,
        "peers" => [1, 2],
        "newSnapshotHash" => "abc",
        "localFrontier" => "lf",
        "remoteFrontier" => "rf"
      }

      expected = %{
        ops_applied: 3,
        peers: [1, 2],
        new_snapshot_hash: "abc",
        local_frontier: "lf",
        remote_frontier: "rf"
      }

      assert Types.normalize_merge_summary(snake) == expected
      assert Types.normalize_merge_summary(camel) == expected
    end

    test "missing fields default safely" do
      assert Types.normalize_merge_summary(%{}) == %{
               ops_applied: 0,
               peers: [],
               new_snapshot_hash: "",
               local_frontier: "",
               remote_frontier: ""
             }
    end
  end
end
