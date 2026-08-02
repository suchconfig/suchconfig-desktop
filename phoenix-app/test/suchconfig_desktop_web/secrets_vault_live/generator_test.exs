defmodule SuchConfigDesktopWeb.SecretsVaultLive.GeneratorTest do
  use ExUnit.Case, async: true

  alias SuchConfigCore.Generators.PasswordGenerator
  alias SuchConfigDesktopWeb.SecretsVaultLive.Generator

  setup do
    wordlist = Path.expand("../../fixtures/eff_wordlist_sample.txt", __DIR__)

    Application.put_env(
      :suchconfig_core,
      :eff_wordlist_path,
      wordlist
    )

    on_exit(fn ->
      Application.delete_env(:suchconfig_core, :eff_wordlist_path)
    end)

    :ok
  end

  test "password mode uses PasswordGenerator" do
    assert {:ok, value, _meta, level, label} =
             Generator.generate_from_assigns(%{
               generator_mode: "password",
               generator_length: 16,
               generator_opts: Generator.default_opts()
             })

    assert is_binary(value)
    assert byte_size(value) == 16
    assert level in 1..5
    assert is_binary(label)
  end

  test "passphrase mode uses PasswordGenerator wordlist" do
    assert {:ok, value, _meta, _level, _label} =
             Generator.generate_from_assigns(%{
               generator_mode: "passphrase",
               generator_length: 20,
               generator_opts: %{num: true}
             })

    assert value =~ "-"
    assert String.split(value, "-") |> length() >= 4
  end

  test "username mode generates random local username" do
    assert {:ok, value, _meta, _level, _label} =
             Generator.generate_from_assigns(%{
               generator_mode: "username",
               generator_length: 10,
               generator_opts: Map.put(Generator.default_opts(), :gmail_alias, false)
             })

    assert is_binary(value)
    assert byte_size(value) == 10
    assert value =~ ~r/^[a-z0-9]+$/
  end

  test "username mode generates gmail plus alias with random suffix" do
    assert {:ok, value, _meta, 0, "alias"} =
             Generator.generate_from_assigns(%{
               generator_mode: "username",
               generator_length: 6,
               generator_opts:
                 Generator.default_opts()
                 |> Map.put(:gmail_alias, true)
                 |> Map.put(:gmail_base, "testuser@gmail.com")
                 |> Map.put(:alias_random, true)
             })

    assert value =~ ~r/^testuser\+[a-z0-9]+@gmail\.com$/
  end

  test "username mode expands structured alias pattern" do
    assert {:ok, value, _meta, 0, "alias"} =
             Generator.generate_from_assigns(%{
               generator_mode: "username",
               generator_length: 8,
               generator_opts:
                 Generator.default_opts()
                 |> Map.put(:gmail_alias, true)
                 |> Map.put(:gmail_base, "me@gmail.com")
                 |> Map.put(:alias_random, false)
                 |> Map.put(:alias_pattern, "{env}.{project}.{date_compact}")
                 |> Map.put(:tag_env, "staging")
                 |> Map.put(:tag_project, "suchconfig")
             })

    assert value =~ ~r/^me\+staging\.suchconfig\.\d{8}@gmail\.com$/
  end

  test "mode_from_params picks target-specific default mode" do
    assert Generator.mode_from_params(%{"target" => "username"}, :secrets_entry) == "username"
    assert Generator.mode_from_params(%{"target" => "password"}, :secrets_entry) == "password"
    assert Generator.mode_from_params(%{}, :standalone) == "password"
  end

  test "format_error for missing gmail base" do
    assert Generator.format_error(:missing_gmail_base) =~ "Gmail"
  end

  test "format_error for missing wordlist mentions fetch task" do
    assert Generator.format_error(:wordlist_file_missing) =~ "fetch_eff_wordlist"
  end

  test "default length matches core default" do
    assert Generator.default_length() == PasswordGenerator.default_password_length()
  end
end
