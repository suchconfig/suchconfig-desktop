defmodule SuchConfigDesktop.SecretsVault.Types do
  @moduledoc false

  @kinds [:password, :api_key, :ssh_key, :secure_note]
  @kind_strings Enum.map(@kinds, &Atom.to_string/1)

  @security_modes [:global_passkey]
  @security_mode_strings Enum.map(@security_modes, &Atom.to_string/1)

  @type kind :: :password | :api_key | :ssh_key | :secure_note
  @type security_mode :: :global_passkey

  @spec allowed_kinds() :: [kind()]
  def allowed_kinds, do: @kinds

  @spec allowed_kind_strings() :: [String.t()]
  def allowed_kind_strings, do: @kind_strings

  @spec allowed_security_modes() :: [security_mode()]
  def allowed_security_modes, do: @security_modes

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

  defp safe_atom_from_allowlist(string, allowed_atoms) do
    Enum.find(allowed_atoms, fn atom -> Atom.to_string(atom) == string end)
  end
end
