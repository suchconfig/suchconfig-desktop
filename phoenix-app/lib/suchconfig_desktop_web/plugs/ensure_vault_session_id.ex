defmodule SuchConfigDesktopWeb.Plugs.EnsureVaultSessionId do
  @moduledoc """
  Ensures the session has a stable vault_session_id for app-wide Global Passkey state.
  Must run after fetch_session.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    ensure_vault_session_id(conn)
  end

  defp ensure_vault_session_id(conn) do
    id = get_session(conn, "vault_session_id") || Ecto.UUID.generate()
    put_session(conn, "vault_session_id", id)
  end
end
