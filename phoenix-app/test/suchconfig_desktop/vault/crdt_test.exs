defmodule SuchConfigDesktop.Vault.CrdtTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.Vault.Crdt

  setup context do
    if Map.get(context, :crdt_nif_required, false) and not Crdt.available?() do
      {:skip, "Rustler NIF `vault_crdt` not loaded; run `mix deps.compile` with Rust toolchain"}
    else
      :ok
    end
  end

  describe "available?/0" do
    test "returns a boolean without raising" do
      assert is_boolean(Crdt.available?())
    end
  end

  describe "new_doc/1" do
    @tag :crdt_nif_required
    test "creates an encoded snapshot for every supported kind" do
      project_kinds = ~w(env_note generic_note prompt_template guideline api_spec security_policy)
      credential_kinds = ~w(password api_key ssh_key secure_note)
      all_kinds = project_kinds ++ credential_kinds

      for kind <- all_kinds do
        assert {:ok, snap} = Crdt.new_doc(kind)
        assert is_binary(snap)
        assert byte_size(snap) > 0
        assert {:ok, decoded} = Crdt.decode_kind(snap)
        assert Atom.to_string(decoded) == kind
      end
    end

    @tag :crdt_nif_required
    test "credential kinds support body and frontmatter round-trip" do
      {:ok, snap} = Crdt.new_doc("password")
      {:ok, snap} = Crdt.set_body(snap, "placeholder-secret")

      {:ok, snap} =
        Crdt.apply_frontmatter(snap, %{
          "username" => "user@example.com",
          "url" => "https://example.com"
        })

      assert {:ok, "placeholder-secret"} = Crdt.body(snap)
      assert {:ok, "user@example.com"} = Crdt.frontmatter_string(snap, "username")
    end

    test "rejects unknown kind without crashing (NIF up or down)" do
      case Crdt.new_doc(:not_a_kind) do
        {:error, :unknown_kind, _msg} -> :ok
        {:error, :nif_unavailable, _msg} -> :ok
      end
    end

    @tag :crdt_nif_required
    test "coerces string kind like form params" do
      assert {:ok, snap} = Crdt.new_doc("prompt_template")
      assert {:ok, :prompt_template} = Crdt.decode_kind(snap)
    end
  end

  describe "set_body / body round-trip" do
    @tag :crdt_nif_required
    test "body set on snapshot survives re-decode" do
      {:ok, snap} = Crdt.new_doc(:generic_note)
      {:ok, updated} = Crdt.set_body(snap, "hello, crdt world\n")
      assert {:ok, "hello, crdt world\n"} = Crdt.body(updated)
    end
  end

  describe "apply_update / diff_from" do
    @tag :crdt_nif_required
    test "two independent peers converge on body after exchanging updates" do
      {:ok, root_a} = Crdt.new_doc(:prompt_template)
      {:ok, root_b} = Crdt.new_doc(:prompt_template)
      {:ok, peer_a} = Crdt.set_body(root_a, "alpha")
      {:ok, peer_b} = Crdt.set_body(root_b, "beta")

      {:ok, a_to_b} = Crdt.diff_from(peer_a, peer_b)
      {:ok, b_to_a} = Crdt.diff_from(peer_b, peer_a)

      {:ok, merged_b, summary_b} = Crdt.apply_update(peer_b, a_to_b)
      {:ok, merged_a, summary_a} = Crdt.apply_update(peer_a, b_to_a)

      assert {:ok, body_a} = Crdt.body(merged_a)
      assert {:ok, body_b} = Crdt.body(merged_b)
      assert body_a == body_b

      assert summary_a.ops_applied >= 1
      assert summary_b.ops_applied >= 1
      assert is_binary(summary_a.new_snapshot_hash)
      assert is_binary(summary_b.new_snapshot_hash)
    end

    @tag :crdt_nif_required
    test "applying the same update twice is idempotent at the body level" do
      {:ok, base} = Crdt.new_doc(:guideline)
      {:ok, edited} = Crdt.set_body(base, "Revocation: 24h")
      {:ok, update} = Crdt.diff_from(edited, base)

      {:ok, first, summary1} = Crdt.apply_update(base, update)
      {:ok, second, summary2} = Crdt.apply_update(first, update)

      assert {:ok, "Revocation: 24h"} = Crdt.body(first)
      assert {:ok, "Revocation: 24h"} = Crdt.body(second)
      assert summary1.ops_applied > 0
      assert summary2.ops_applied <= summary1.ops_applied
    end

    @tag :crdt_nif_required
    test "corrupted update bytes return an error tuple, never crash" do
      {:ok, snap} = Crdt.new_doc(:env_note)
      assert {:error, reason, _} = Crdt.apply_update(snap, "not-a-real-update")
      assert reason in [:delta_decode, :snapshot_decode, :loro]
    end
  end

  describe "graceful fallback when NIF is unavailable" do
    test "every public function returns an error tuple when NIF missing" do
      unless Crdt.available?() do
        assert match?({:error, :nif_unavailable, _}, Crdt.new_doc(:generic_note))
        assert match?({:error, :nif_unavailable, _}, Crdt.decode_kind(<<0>>))
        assert match?({:error, :nif_unavailable, _}, Crdt.body(<<0>>))
        assert match?({:error, :nif_unavailable, _}, Crdt.set_body(<<0>>, "x"))
        assert match?({:error, :nif_unavailable, _}, Crdt.apply_update(<<0>>, <<0>>))
        assert match?({:error, :nif_unavailable, _}, Crdt.diff_from(<<0>>, <<0>>))
        assert match?({:error, :nif_unavailable, _}, Crdt.snapshot_hash(<<0>>))
      end
    end
  end
end
