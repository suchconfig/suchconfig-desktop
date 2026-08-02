defmodule SuchConfigDesktop.VaultSessionRegistry do
  @moduledoc """
  In-memory registry for the vault key per session. Used so the app-level unlock
  (AppLive) can share the key with Project Manager and other features without
  putting secrets in the connection session.
  """
  use GenServer

  @table __MODULE__

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get(session_id) when is_binary(session_id) do
    case :ets.whereis(@table) do
      :undefined ->
        nil

      _ ->
        case :ets.lookup(@table, session_id) do
          [{^session_id, key}] when is_binary(key) -> key
          _ -> nil
        end
    end
  end

  def put(session_id, key) when is_binary(session_id) and is_binary(key) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.insert(@table, {session_id, key})
        :ok
    end
  end

  def delete(session_id) when is_binary(session_id) do
    case :ets.whereis(@table) do
      :undefined ->
        :ok

      _ ->
        :ets.delete(@table, session_id)
        :ok
    end
  end

  @impl true
  def init(_opts) do
    tab = :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    {:ok, tab}
  end
end
