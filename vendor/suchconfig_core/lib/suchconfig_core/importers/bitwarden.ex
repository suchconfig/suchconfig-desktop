defmodule SuchConfigCore.Importers.Bitwarden do
  @moduledoc """
  Parses Bitwarden unencrypted JSON vault exports into `ImportData`.

  Supports CipherType: Login (1), Secure Note (2), Card (3), Identity (4), SSH Key (5).
  Encrypted exports return `{:error, :encrypted_export}`. Attachments are metadata warnings only.
  """

  alias SuchConfigCore.Importers.ImportData

  @type_login 1
  @type_secure_note 2
  @type_card 3
  @type_identity 4
  @type_ssh_key 5

  @doc """
  Parses a Bitwarden unencrypted JSON export string or already-decoded map.
  """
  @spec parse_json(binary() | map()) :: {:ok, ImportData.t()} | {:error, term()}
  def parse_json(payload) when is_binary(payload) do
    case Jason.decode(payload) do
      {:ok, data} when is_map(data) -> parse_json(data)
      {:ok, _} -> {:error, :invalid_bitwarden_json}
      {:error, _} -> {:error, :invalid_json}
    end
  end

  def parse_json(%{} = data) do
    cond do
      Map.get(data, "encrypted") == true ->
        {:error, :encrypted_export}

      not is_list(Map.get(data, "items", [])) ->
        {:error, :invalid_bitwarden_json}

      true ->
        folders = normalize_folders(Map.get(data, "folders", []))
        folder_by_id = Map.new(folders, fn f -> {f.external_id, f.name} end)
        warnings = []

        {items, warnings} =
          data
          |> Map.get("items", [])
          |> Enum.reduce({[], warnings}, fn raw, {acc, warns} ->
            case normalize_item(raw, folder_by_id) do
              {:ok, item, extra_warns} ->
                {[item | acc], warns ++ extra_warns}

              :skip ->
                {acc, warns}
            end
          end)

        {:ok,
         %ImportData{
           source: :bitwarden,
           folders: folders,
           items: Enum.reverse(items),
           warnings: warnings
         }}
    end
  end

  def parse_json(_), do: {:error, :invalid_bitwarden_json}

  defp normalize_folders(folders) when is_list(folders) do
    folders
    |> Enum.map(fn
      %{"id" => id, "name" => name} when is_binary(name) ->
        name = String.trim(name)

        if name == "" do
          nil
        else
          %{external_id: to_string(id), name: name}
        end

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_folders(_), do: []

  defp normalize_item(%{"deletedDate" => deleted}, _folders)
       when not is_nil(deleted) and deleted != "",
       do: :skip

  defp normalize_item(%{} = raw, folder_by_id) do
    type = Map.get(raw, "type")
    title = raw |> Map.get("name", "") |> to_string() |> String.trim()
    title = if title == "", do: "Untitled", else: title
    folder_id = Map.get(raw, "folderId")
    folder_name = if folder_id, do: Map.get(folder_by_id, to_string(folder_id)), else: nil
    notes = raw |> Map.get("notes") |> stringify()
    external_id = raw |> Map.get("id") |> stringify_id()
    warnings = attachment_warnings(raw, title)

    {kind, body, frontmatter, type_warns} = map_cipher(type, raw, notes)

    item = %{
      external_id: external_id,
      folder_name: folder_name,
      kind: kind,
      title: title,
      body: body,
      frontmatter: frontmatter,
      skipped?: false,
      skip_reason: nil
    }

    {:ok, item, warnings ++ type_warns}
  end

  defp normalize_item(_, _), do: :skip

  defp map_cipher(@type_login, raw, notes) do
    login = Map.get(raw, "login") || %{}
    password = login |> Map.get("password") |> stringify()
    username = login |> Map.get("username") |> stringify()
    totp = login |> Map.get("totp") |> stringify()
    url = first_uri(login)
    ssh? = ssh_private_key?(password) or ssh_private_key?(notes)

    frontmatter =
      %{}
      |> put_fm("username", username)
      |> put_fm("url", url)
      |> put_fm("totp", totp)
      |> put_fm("notes", notes)

    cond do
      ssh? ->
        body = if ssh_private_key?(password), do: password, else: notes
        public = extract_ssh_public(raw, notes)

        fm =
          frontmatter
          |> put_fm("public_key", public)
          |> Map.delete("notes")
          |> maybe_drop_login_fields()

        {"ssh_key", body, fm, []}

      true ->
        {"password", password, frontmatter, []}
    end
  end

  defp map_cipher(@type_secure_note, _raw, notes) do
    {"secure_note", notes, %{}, []}
  end

  defp map_cipher(@type_card, raw, notes) do
    card = Map.get(raw, "card") || %{}
    body = serialize_card(card, notes)
    warn = ["Card \"#{Map.get(raw, "name", "item")}\" imported as secure note"]
    {"secure_note", body, %{}, warn}
  end

  defp map_cipher(@type_identity, raw, notes) do
    identity = Map.get(raw, "identity") || %{}
    body = serialize_identity(identity, notes)
    warn = ["Identity \"#{Map.get(raw, "name", "item")}\" imported as secure note"]
    {"secure_note", body, %{}, warn}
  end

  defp map_cipher(@type_ssh_key, raw, notes) do
    ssh = Map.get(raw, "sshKey") || Map.get(raw, "ssh_key") || %{}
    private = ssh |> Map.get("privateKey") |> stringify()
    private = if private == "", do: notes, else: private
    public = ssh |> Map.get("publicKey") |> stringify()
    fingerprint = ssh |> Map.get("keyFingerprint") |> stringify()

    fm =
      %{}
      |> put_fm("public_key", public)
      |> put_fm("fingerprint", fingerprint)

    {"ssh_key", private, fm, []}
  end

  defp map_cipher(_type, raw, notes) do
    fields = serialize_custom_fields(Map.get(raw, "fields", []))
    body = join_nonempty([notes, fields])
    warn = ["Unknown Bitwarden type for \"#{Map.get(raw, "name", "item")}\" imported as secure note"]
    {"secure_note", body, %{}, warn}
  end

  defp attachment_warnings(%{"attachments" => attachments}, title)
       when is_list(attachments) and attachments != [] do
    count = length(attachments)
    ["\"#{title}\" has #{count} attachment(s) — metadata only; file bytes not imported"]
  end

  defp attachment_warnings(_, _), do: []

  defp first_uri(%{"uris" => [%{"uri" => uri} | _]}) when is_binary(uri), do: String.trim(uri)
  defp first_uri(%{"uris" => [uri | _]}) when is_binary(uri), do: String.trim(uri)
  defp first_uri(_), do: ""

  defp serialize_card(card, notes) when is_map(card) do
    lines =
      [
        {"Cardholder", Map.get(card, "cardholderName")},
        {"Brand", Map.get(card, "brand")},
        {"Number", Map.get(card, "number")},
        {"Exp month", Map.get(card, "expMonth")},
        {"Exp year", Map.get(card, "expYear")},
        {"Code", Map.get(card, "code")}
      ]
      |> Enum.map(fn {label, val} ->
        val = stringify(val)
        if val == "", do: nil, else: "#{label}: #{val}"
      end)
      |> Enum.reject(&is_nil/1)

    join_nonempty(lines ++ [notes_suffix(notes)])
  end

  defp serialize_card(_, notes), do: notes

  defp serialize_identity(identity, notes) when is_map(identity) do
    keys = [
      {"Title", "title"},
      {"First name", "firstName"},
      {"Middle name", "middleName"},
      {"Last name", "lastName"},
      {"Username", "username"},
      {"Company", "company"},
      {"SSN", "ssn"},
      {"Passport", "passportNumber"},
      {"License", "licenseNumber"},
      {"Email", "email"},
      {"Phone", "phone"},
      {"Address 1", "address1"},
      {"Address 2", "address2"},
      {"Address 3", "address3"},
      {"City", "city"},
      {"State", "state"},
      {"Postal", "postalCode"},
      {"Country", "country"}
    ]

    lines =
      Enum.map(keys, fn {label, key} ->
        val = identity |> Map.get(key) |> stringify()
        if val == "", do: nil, else: "#{label}: #{val}"
      end)
      |> Enum.reject(&is_nil/1)

    join_nonempty(lines ++ [notes_suffix(notes)])
  end

  defp serialize_identity(_, notes), do: notes

  defp serialize_custom_fields(fields) when is_list(fields) do
    fields
    |> Enum.map(fn
      %{"name" => name, "value" => value} ->
        n = stringify(name)
        v = stringify(value)
        if n == "" and v == "", do: nil, else: "#{n}: #{v}"

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp serialize_custom_fields(_), do: ""

  defp extract_ssh_public(raw, notes) do
    fields = Map.get(raw, "fields", [])

    from_field =
      Enum.find_value(fields, fn
        %{"name" => name, "value" => value} when is_binary(value) ->
          if String.contains?(String.downcase(to_string(name)), "public"), do: value, else: nil

        _ ->
          nil
      end)

    cond do
      is_binary(from_field) and from_field != "" -> from_field
      String.contains?(notes, "ssh-") -> notes
      true -> ""
    end
  end

  defp ssh_private_key?(text) when is_binary(text) do
    String.contains?(text, "BEGIN OPENSSH PRIVATE KEY") or
      String.contains?(text, "BEGIN RSA PRIVATE KEY") or
      String.contains?(text, "BEGIN EC PRIVATE KEY")
  end

  defp ssh_private_key?(_), do: false

  defp maybe_drop_login_fields(fm) do
    fm
    |> Map.delete("username")
    |> Map.delete("url")
  end

  defp put_fm(map, _key, ""), do: map
  defp put_fm(map, _key, nil), do: map
  defp put_fm(map, key, value) when is_binary(value), do: Map.put(map, key, value)
  defp put_fm(map, key, value), do: Map.put(map, key, to_string(value))

  defp notes_suffix(""), do: nil
  defp notes_suffix(notes), do: notes

  defp join_nonempty(parts) do
    parts
    |> Enum.reject(&(is_nil(&1) or &1 == ""))
    |> Enum.join("\n\n")
  end

  defp stringify(nil), do: ""
  defp stringify(v) when is_binary(v), do: String.trim(v)
  defp stringify(v), do: v |> to_string() |> String.trim()

  defp stringify_id(nil), do: nil
  defp stringify_id(id), do: to_string(id)
end
