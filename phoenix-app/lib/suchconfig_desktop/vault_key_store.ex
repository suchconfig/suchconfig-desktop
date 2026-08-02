defmodule SuchConfigDesktop.VaultKeyStore do
  import Ecto.Query, warn: false

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.VaultKey

  def get(key_id) do
    Repo.one(from v in VaultKey, where: v.key_id == ^key_id, select: v.key_text)
  end

  def put(key_id, key_text) when is_binary(key_id) and is_binary(key_text) do
    case Repo.get_by(VaultKey, key_id: key_id) do
      nil ->
        %VaultKey{}
        |> VaultKey.changeset(%{key_id: key_id, key_text: key_text})
        |> Repo.insert()

      existing ->
        existing
        |> VaultKey.changeset(%{key_text: key_text})
        |> Repo.update()
    end
  end

  def delete(key_id) do
    case Repo.get_by(VaultKey, key_id: key_id) do
      nil -> {:ok, nil}
      row -> Repo.delete(row)
    end
  end
end
