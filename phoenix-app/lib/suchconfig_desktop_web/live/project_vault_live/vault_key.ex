defmodule SuchConfigDesktopWeb.ProjectVaultLive.VaultKey do
  @moduledoc """
  Vault key lifecycle helpers used by the Project Vault LiveView.

  Resolves the in-session vault key from the session registry (and falls back
  to the Tauri-side store), exposes a session-key generator for first-time
  setup, and wraps `ProjectVault.decrypt_note_raw_content/2` with simple
  argument guards.
  """

  import Phoenix.Component, only: [assign: 2]

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.VaultKeyStore
  alias SuchConfigDesktop.VaultSessionRegistry

  @vault_key_id "suchconfig.project_manager.vault"

  def vault_key_id, do: @vault_key_id

  def new_session_vault_key do
    32 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end

  def session_global_passkey_unlocked?(socket) do
    socket.assigns.global_passkey_unlocked and
      is_binary(socket.assigns.vault_password) and
      String.trim(socket.assigns.vault_password) != ""
  end

  def ensure_vault_key_from_registry(socket) do
    session_id = socket.assigns[:vault_session_id]

    key =
      if is_binary(session_id) and String.trim(session_id) != "" do
        VaultSessionRegistry.get(session_id)
      else
        nil
      end

    key =
      if is_binary(key) and String.trim(key) != "" do
        key
      else
        VaultKeyStore.get(@vault_key_id)
      end

    if is_binary(key) and String.trim(key) != "" do
      if is_binary(session_id) and String.trim(session_id) != "" do
        VaultSessionRegistry.put(session_id, key)
      end

      assign(socket, vault_password: key, global_passkey_unlocked: true)
    else
      socket
    end
  end

  def decrypt_note_content(%{encryption_version: 0} = note, _password) do
    ProjectVault.decrypt_note_raw_content(note, "")
  end

  def decrypt_note_content(_note, ""), do: {:error, :missing_password}

  def decrypt_note_content(note, password) do
    ProjectVault.decrypt_note_raw_content(note, password)
  end
end
