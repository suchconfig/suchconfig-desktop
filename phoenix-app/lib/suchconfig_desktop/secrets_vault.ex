defmodule SuchConfigDesktop.SecretsVault do
  @moduledoc """
  Application boundary for the Secrets Vault (credentials CRDT store).
  """

  import Ecto.Query, warn: false

  alias SuchConfigDesktop.Repo
  alias SuchConfigDesktop.SecretsVault.Folder
  alias SuchConfigDesktop.SecretsVault.Item
  alias SuchConfigDesktop.SecretsVault.Types
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigCore.Security.EnvCrypto

  def feature_enabled?, do: Crdt.available?()

  def secrets_vault_enabled? do
    Application.get_env(:suchconfig_desktop, :secrets_vault_enabled, true) == true
  end

  def crdt_persistence_enabled? do
    Application.get_env(:suchconfig_desktop, :secrets_vault_crdt_persistence, true) == true
  end

  def list_folders do
    from(f in Folder, order_by: [asc: f.name, asc: f.id]) |> Repo.all()
  end

  def get_folder!(id), do: Repo.get!(Folder, id)

  def create_folder(attrs) do
    %Folder{}
    |> Folder.changeset(attrs)
    |> Repo.insert()
  end

  def update_folder(%Folder{} = folder, attrs) do
    folder
    |> Folder.changeset(attrs)
    |> Repo.update()
  end

  def delete_folder(%Folder{} = folder) do
    Repo.delete(folder)
  end

  def ensure_unassociated_folder do
    ensure_system_folder(
      Folder.unassociated_name(),
      "Default folder for secrets without a folder"
    )
  end

  def ensure_uncategorized_folder, do: ensure_unassociated_folder()

  defp ensure_system_folder(name, description) do
    case Repo.get_by(Folder, name: name) do
      %Folder{} = folder ->
        {:ok, folder}

      nil ->
        case Repo.get_by(Folder, name: "Uncategorized") do
          %Folder{} = legacy ->
            legacy
            |> Folder.changeset(%{name: name, description: description})
            |> Repo.update()

          nil ->
            case create_folder(%{name: name, description: description}) do
              {:ok, folder} ->
                {:ok, folder}

              {:error, changeset} ->
                case Repo.get_by(Folder, name: name) do
                  %Folder{} = folder -> {:ok, folder}
                  nil -> {:error, changeset}
                end
            end
        end
    end
  end

  def list_items(folder_id) when is_integer(folder_id) do
    from(i in Item,
      where: i.secrets_vault_folder_id == ^folder_id,
      order_by: [asc: i.title, asc: i.id]
    )
    |> Repo.all()
  end

  def list_items(nil) do
    from(i in Item, order_by: [asc: i.title, asc: i.id]) |> Repo.all()
  end

  def get_item(id), do: Repo.get(Item, id)

  def get_item!(id), do: Repo.get!(Item, id)

  def delete_item(id) when is_integer(id) do
    case Repo.get(Item, id) do
      nil -> {:error, :not_found}
      %Item{} = item -> Repo.delete(item)
    end
  end

  def delete_item(_), do: {:error, :not_found}

  def save_item(attrs, password) when is_map(attrs) and is_binary(password) and password != "" do
    with :ok <- ensure_persistence(),
         {:ok, normalized} <- normalize_item_attrs(attrs),
         :ok <- validate_folder(normalized.secrets_vault_folder_id),
         {:ok, item} <- persist_item(normalized, password) do
      {:ok, item}
    end
  end

  def save_item(_attrs, _password), do: {:error, :invalid_password}

  def decrypt_item_body(%Item{} = item, password)
      when is_binary(password) and password != "" do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, body} <- Crdt.body(plain) do
      {:ok, body}
    else
      _ -> {:error, :invalid_password}
    end
  end

  def decrypt_item_body(_item, _password), do: {:error, :invalid_password}

  def decrypt_item_frontmatter(%Item{} = item, password)
      when is_binary(password) and password != "" do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, fm} <- frontmatter_map(plain) do
      {:ok, fm}
    else
      _ -> {:error, :invalid_password}
    end
  end

  def decrypt_item_frontmatter(_item, _password), do: {:error, :invalid_password}

  def item_frontmatter(%Item{} = item, password, key)
      when is_binary(password) and is_binary(key) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, val} <- Crdt.frontmatter_string(plain, key) do
      {:ok, val}
    else
      _ -> {:error, :invalid_password}
    end
  end

  def search_items(folder_id, query, password)
      when is_binary(query) and is_binary(password) and password != "" do
    query = String.trim(query) |> String.downcase()

    folder_id
    |> list_items()
    |> Enum.filter(fn item ->
      title_match = String.downcase(item.title) |> String.contains?(query)

      meta_match =
        if query == "" do
          true
        else
          case decrypt_item_frontmatter(item, password) do
            {:ok, fm} ->
              username = String.downcase(Map.get(fm, "username", ""))
              url = String.downcase(Map.get(fm, "url", ""))
              String.contains?(username, query) or String.contains?(url, query)

            _ ->
              false
          end
        end

      query == "" or title_match or meta_match
    end)
  end

  def search_items(folder_id, "", _password), do: list_items(folder_id)

  def search_items(_folder_id, _query, _password), do: []

  def format_error(reason) when is_atom(reason),
    do: Atom.to_string(reason) |> String.replace("_", " ")

  def format_error(reason) when is_binary(reason), do: reason
  def format_error(_), do: "Operation failed."

  defp ensure_persistence do
    cond do
      not crdt_persistence_enabled?() -> {:error, :secrets_vault_persistence_disabled}
      not feature_enabled?() -> {:error, :crdt_unavailable}
      true -> :ok
    end
  end

  defp normalize_item_attrs(attrs) do
    title = attrs |> take_attr(:title) |> trim()
    kind = take_attr(attrs, :kind)
    security_mode = take_attr(attrs, :security_mode) || "global_passkey"
    folder_id = take_attr(attrs, :secrets_vault_folder_id)
    body = take_attr(attrs, :body) |> default_string()
    id = take_attr(attrs, :id)
    frontmatter = normalize_frontmatter(take_attr(attrs, :frontmatter))

    with {:ok, id} <- cast_optional_id(id),
         true <- title != "",
         {:ok, kind_atom} <- Types.cast_kind(kind),
         {:ok, mode_atom} <- Types.cast_security_mode(security_mode),
         {:ok, folder_id} <- resolve_folder_id(folder_id) do
      {:ok,
       %{
         id: id,
         title: title,
         kind: Atom.to_string(kind_atom),
         security_mode: Atom.to_string(mode_atom),
         secrets_vault_folder_id: folder_id,
         body: body,
         frontmatter: frontmatter
       }}
    else
      false -> {:error, :invalid_title}
      {:error, _} = err -> err
    end
  end

  defp resolve_folder_id(nil), do: unassociated_folder_id()
  defp resolve_folder_id(""), do: unassociated_folder_id()
  defp resolve_folder_id(id), do: cast_positive_int(id)

  defp unassociated_folder_id do
    case ensure_unassociated_folder() do
      {:ok, folder} -> {:ok, folder.id}
      {:error, _} = err -> err
    end
  end

  defp normalize_frontmatter(nil), do: %{}

  defp normalize_frontmatter(%{} = m),
    do: Map.new(m, fn {k, v} -> {to_string(k), to_string(v)} end)

  defp normalize_frontmatter(_), do: %{}

  defp frontmatter_map(snap) do
    keys = ["username", "url", "public_key", "fingerprint", "hostname", "tags", "project_ref"]

    fm =
      Enum.reduce(keys, %{}, fn key, acc ->
        case Crdt.frontmatter_string(snap, key) do
          {:ok, val} when is_binary(val) and val != "" -> Map.put(acc, key, val)
          _ -> acc
        end
      end)

    {:ok, fm}
  end

  defp validate_folder(folder_id) do
    case Repo.get(Folder, folder_id) do
      %Folder{} -> :ok
      nil -> {:error, :invalid_folder}
    end
  end

  defp persist_item(%{id: nil} = n, password) do
    with {:ok, snap} <- Crdt.new_doc(n.kind),
         {:ok, snap} <- Crdt.set_body(snap, n.body),
         {:ok, snap} <- apply_frontmatter(snap, n.frontmatter),
         {:ok, hash} <- Crdt.snapshot_hash(snap),
         {:ok, enc_bin} <- EnvCrypto.encrypt_to_binary(password, snap) do
      %Item{}
      |> Item.changeset(%{
        title: n.title,
        kind: n.kind,
        security_mode: n.security_mode,
        secrets_vault_folder_id: n.secrets_vault_folder_id,
        crdt_snapshot_encrypted: enc_bin,
        crdt_snapshot_nonce: nil,
        crdt_encryption_version: 1,
        crdt_schema_version: 1,
        crdt_snapshot_hash: hash,
        updated_clock: System.system_time(:millisecond)
      })
      |> Repo.insert()
    else
      {:error, _} -> {:error, :encrypt_failed}
      {:error, _, _} -> {:error, :crdt_error}
    end
  end

  defp persist_item(%{id: id} = n, password) when is_integer(id) do
    case Repo.get(Item, id) do
      nil ->
        {:error, :not_found}

      %Item{} = item ->
        do_update_item(item, n, password)
    end
  end

  defp persist_item(_, _), do: {:error, :invalid_attrs}

  defp do_update_item(%Item{} = item, n, password) do
    with {:ok, plain} <- EnvCrypto.decrypt_from_binary(password, item.crdt_snapshot_encrypted),
         {:ok, snap} <- Crdt.set_body(plain, n.body),
         {:ok, snap} <- apply_frontmatter(snap, n.frontmatter),
         {:ok, hash} <- Crdt.snapshot_hash(snap),
         {:ok, enc_bin} <- EnvCrypto.encrypt_to_binary(password, snap) do
      item
      |> Item.changeset(%{
        title: n.title,
        kind: n.kind,
        security_mode: n.security_mode,
        secrets_vault_folder_id: n.secrets_vault_folder_id,
        crdt_snapshot_encrypted: enc_bin,
        crdt_encryption_version: 1,
        crdt_schema_version: 1,
        crdt_snapshot_hash: hash,
        updated_clock: System.system_time(:millisecond)
      })
      |> Repo.update()
    else
      {:error, :invalid_password_or_payload} -> {:error, :invalid_password}
      {:error, _} -> {:error, :encrypt_failed}
      {:error, _, _} -> {:error, :crdt_error}
    end
  end

  defp apply_frontmatter(snap, fm) when map_size(fm) == 0, do: {:ok, snap}
  defp apply_frontmatter(snap, fm), do: Crdt.apply_frontmatter(snap, fm)

  defp cast_optional_id(nil), do: {:ok, nil}
  defp cast_optional_id(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp cast_optional_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_id}
    end
  end

  defp cast_optional_id(_), do: {:error, :invalid_id}

  defp cast_positive_int(id) when is_integer(id) and id > 0, do: {:ok, id}

  defp cast_positive_int(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} when n > 0 -> {:ok, n}
      _ -> {:error, :invalid_folder}
    end
  end

  defp cast_positive_int(_), do: {:error, :invalid_folder}

  defp take_attr(attrs, key) when is_atom(key) do
    Map.get(attrs, key) || Map.get(attrs, Atom.to_string(key))
  end

  defp trim(nil), do: ""
  defp trim(s) when is_binary(s), do: String.trim(s)
  defp trim(s), do: s |> to_string() |> String.trim()

  defp default_string(nil), do: ""
  defp default_string(s) when is_binary(s), do: s
  defp default_string(s), do: to_string(s)
end
