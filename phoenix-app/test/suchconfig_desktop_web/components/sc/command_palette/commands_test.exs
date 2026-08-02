defmodule SuchConfigDesktopWeb.Sc.CommandPalette.CommandsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.Sc.CommandPalette.Commands

  test "groups include navigate create and vault sections when secrets enabled" do
    groups = Commands.groups(true)
    ids = groups |> Commands.flat_items() |> Enum.map(& &1.id)

    assert Enum.any?(groups, &(&1.group == "Navigate"))
    assert Enum.any?(groups, &(&1.group == "Create"))
    assert Enum.any?(groups, &(&1.group == "Vault"))
    assert "new.login" in ids
    assert "nav.sec" in ids
    assert "nav.settings" in ids
    assert "import" in ids
    assert "export" in ids
  end

  test "groups omit secrets create items when secrets disabled" do
    ids =
      false
      |> Commands.groups()
      |> Commands.flat_items()
      |> Enum.map(& &1.id)

    refute "new.login" in ids
    refute "nav.sec" in ids
    assert "new.proj" in ids
    assert "nav.projects" in ids
  end

  test "chord_action resolves linear-style sequences" do
    assert Commands.chord_action("g", "d") == "nav.dash"
    assert Commands.chord_action("g", "w") == "nav.projects"
    assert Commands.chord_action("g", ",") == "nav.settings"
    assert Commands.chord_action("n", "l") == "new.login"
    assert Commands.chord_action("n", "p") == "new.proj"
    assert Commands.chord_action("n", "f") == nil
    assert Commands.chord_action("g", "e") == "export"
    assert Commands.chord_action("g", "i") == "import"
    assert Commands.chord_action("g", "z") == nil
  end

  test "valid_command_id? respects secrets flag" do
    assert Commands.valid_command_id?("nav.docs", true)
    assert Commands.valid_command_id?("nav.settings", true)
    assert Commands.valid_command_id?("new.login", true)
    refute Commands.valid_command_id?("new.login", false)
    refute Commands.valid_command_id?("missing", true)
  end

  test "new project settings and generator items expose expected labels and hints" do
    items =
      true
      |> Commands.groups()
      |> Commands.flat_items()
      |> Map.new(&{&1.id, &1})

    assert items["new.proj"].label == "New project"
    assert items["new.proj"].hint == "N then P"
    assert items["nav.settings"].label == "Open Settings"
    assert items["nav.settings"].hint == "G then ,"
    assert items["nav.gen"].label == "Password Generator"
    assert items["nav.gen"].hint == "G then G"
  end
end
