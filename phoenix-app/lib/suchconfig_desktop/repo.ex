defmodule SuchConfigDesktop.Repo do
  use Ecto.Repo,
    otp_app: :suchconfig_desktop,
    adapter: Ecto.Adapters.SQLite3
end
