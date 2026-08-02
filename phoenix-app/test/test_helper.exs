Application.put_env(
  :suchconfig_core,
  :eff_wordlist_path,
  Path.expand("fixtures/eff_wordlist_sample.txt", __DIR__)
)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(SuchConfigDesktop.Repo, :manual)
