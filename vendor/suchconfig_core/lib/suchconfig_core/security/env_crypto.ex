defmodule SuchConfigCore.Security.EnvCrypto do
  @moduledoc """
  Password-based encryption for environment payloads using AES-256-GCM and PBKDF2.
  """

  @payload_version 1
  @iterations 210_000
  @key_bytes 32
  @salt_bytes 16
  @iv_bytes 12
  @aad "suchconfig-env-manager"

  def encrypt(password, plaintext) when is_binary(password) and is_binary(plaintext) do
    salt = :crypto.strong_rand_bytes(@salt_bytes)
    iv = :crypto.strong_rand_bytes(@iv_bytes)
    key = derive_key(password, salt, @iterations)
    {ciphertext, tag} = :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, plaintext, @aad, true)

    {:ok,
     %{
       "v" => @payload_version,
       "alg" => "aes-256-gcm",
       "kdf" => "pbkdf2-sha256",
       "iter" => @iterations,
       "salt" => Base.encode64(salt),
       "iv" => Base.encode64(iv),
       "ct" => Base.encode64(ciphertext),
       "tag" => Base.encode64(tag)
     }}
  end

  def decrypt(password, payload) when is_binary(password) and is_map(payload) do
    with :ok <- validate_payload(payload),
         {:ok, salt} <- decode64(payload["salt"]),
         {:ok, iv} <- decode64(payload["iv"]),
         {:ok, ciphertext} <- decode64(payload["ct"]),
         {:ok, tag} <- decode64(payload["tag"]) do
      key = derive_key(password, salt, payload["iter"] || @iterations)

      case :crypto.crypto_one_time_aead(:aes_256_gcm, key, iv, ciphertext, @aad, tag, false) do
        plaintext when is_binary(plaintext) -> {:ok, plaintext}
        _ -> {:error, :invalid_password_or_payload}
      end
    else
      _ -> {:error, :invalid_password_or_payload}
    end
  end

  def encode_payload(payload) when is_map(payload), do: Jason.encode(payload)

  def decode_payload(payload_json) when is_binary(payload_json), do: Jason.decode(payload_json)

  def encrypt_to_binary(password, plaintext) do
    with {:ok, payload} <- encrypt(password, plaintext),
         do: encode_payload(payload)
  end

  def decrypt_from_binary(password, payload_json) do
    with {:ok, payload} <- decode_payload(payload_json),
         do: decrypt(password, payload)
  end

  def pack_archive(password, data) when is_binary(password) and is_map(data) do
    with {:ok, json} <- Jason.encode(data),
         do: encrypt_to_binary(password, json)
  end

  def unpack_archive(password, archive_binary) when is_binary(password) and is_binary(archive_binary) do
    with {:ok, json} <- decrypt_from_binary(password, archive_binary),
         {:ok, data} <- Jason.decode(json) do
      {:ok, data}
    else
      _ -> {:error, :invalid_password_or_archive}
    end
  end

  defp derive_key(password, salt, iterations) do
    :crypto.pbkdf2_hmac(:sha256, password, salt, iterations, @key_bytes)
  end

  defp validate_payload(%{"v" => version, "alg" => alg, "kdf" => kdf})
       when version == @payload_version and alg == "aes-256-gcm" and kdf == "pbkdf2-sha256",
       do: :ok

  defp validate_payload(_), do: {:error, :invalid_payload}

  defp decode64(value) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  defp decode64(_), do: {:error, :invalid_base64}
end
