defmodule SuchConfigDesktop.SecretsVault.TypesTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.SecretsVault.Types

  describe "cast_kind/1" do
    test "accepts credential kind strings" do
      for {input, expected} <- [
            {"password", :password},
            {"api_key", :api_key},
            {"ssh_key", :ssh_key},
            {"secure_note", :secure_note}
          ] do
        assert {:ok, ^expected} = Types.cast_kind(input)
      end
    end

    test "accepts allow-listed atoms" do
      for kind <- Types.allowed_kinds() do
        assert {:ok, ^kind} = Types.cast_kind(kind)
      end
    end

    test "rejects project vault kinds and arbitrary strings" do
      assert {:error, :unknown_kind} = Types.cast_kind("generic_note")
      assert {:error, :unknown_kind} = Types.cast_kind("env_note")
      assert {:error, :unknown_kind} = Types.cast_kind("not_a_kind_#{:rand.uniform(1_000_000)}")
    end

    test "rejects invalid types" do
      for bad <- [nil, 42, %{}, :random_atom] do
        assert {:error, :unknown_kind} = Types.cast_kind(bad)
      end
    end
  end

  describe "cast_security_mode/1" do
    test "accepts global_passkey only" do
      assert {:ok, :global_passkey} = Types.cast_security_mode("global_passkey")
      assert {:ok, :global_passkey} = Types.cast_security_mode(:global_passkey)
    end

    test "rejects per_note_password and unknown modes" do
      assert {:error, :unknown_security_mode} = Types.cast_security_mode("per_note_password")
      assert {:error, :unknown_security_mode} = Types.cast_security_mode("none")
    end
  end

  describe "allow-lists" do
    test "allowed_kinds/0 has four credential kinds" do
      assert length(Types.allowed_kinds()) == 4
      assert Types.allowed_kind_strings() == Enum.map(Types.allowed_kinds(), &Atom.to_string/1)
    end
  end
end
