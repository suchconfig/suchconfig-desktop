defmodule SuchConfigDesktop.SecretsVault.KindFields do
  @moduledoc false

  @kinds ~w(password api_key ssh_key secure_note)

  def kinds, do: @kinds

  def normalize_kind("login"), do: "password"
  def normalize_kind(kind) when kind in @kinds, do: kind
  def normalize_kind(_), do: "password"

  def kind_options do
    [
      {"password", "Login"},
      {"api_key", "API key"},
      {"ssh_key", "SSH key"},
      {"secure_note", "Secure note"}
    ]
  end

  def body_label(kind) do
    case normalize_kind(kind) do
      "password" -> "Password"
      "api_key" -> "Secret value"
      "ssh_key" -> "Private key"
      "secure_note" -> "Note"
      _ -> "Secret"
    end
  end

  def body_multiline?(kind), do: normalize_kind(kind) in ["ssh_key", "secure_note"]

  def body_masked?(kind), do: normalize_kind(kind) in ["password", "api_key", "ssh_key"]

  def shows_generator?(kind), do: normalize_kind(kind) in ["password", "api_key"]

  def shows_username?(kind), do: normalize_kind(kind) in ["password", "api_key"]

  def username_label(kind) do
    case normalize_kind(kind) do
      "api_key" -> "Client ID"
      _ -> "Username"
    end
  end

  def shows_url?(kind), do: normalize_kind(kind) in ["password", "api_key"]

  def url_label(kind) do
    case normalize_kind(kind) do
      "api_key" -> "Endpoint URL"
      _ -> "Website URL"
    end
  end

  def shows_ssh_fields?(kind), do: normalize_kind(kind) == "ssh_key"

  def build_frontmatter(kind, fields) when is_map(fields) do
    kind = normalize_kind(kind)

    %{}
    |> maybe_put("username", fields[:username], shows_username?(kind))
    |> maybe_put("url", fields[:url], shows_url?(kind))
    |> maybe_put("public_key", fields[:public_key], shows_ssh_fields?(kind))
    |> maybe_put("fingerprint", fields[:fingerprint], shows_ssh_fields?(kind))
    |> maybe_put("totp", fields[:totp], true)
    |> maybe_put("notes", fields[:notes], true)
  end

  defp maybe_put(map, _key, _value, false), do: map

  defp maybe_put(map, key, value, true) do
    value = if is_binary(value), do: String.trim(value), else: ""

    if value == "" do
      map
    else
      Map.put(map, key, value)
    end
  end
end
