defmodule SuchConfigCore.MixProject do
  use Mix.Project

  @version "0.2.3-ce"

  def project do
    [
      app: :suchconfig_core,
      version: @version,
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:jason, "~> 1.4"},
      {:yaml_elixir, "~> 2.9"}
    ]
  end
end
