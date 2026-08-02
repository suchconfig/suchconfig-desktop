defmodule SuchConfigDesktop.ProjectVault.VaultItemTagsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktop.ProjectVault.VaultItemTags

  test "encode and decode round-trip" do
    assert VaultItemTags.decode(VaultItemTags.encode(["Environment", "Secrets"])) == [
             "Environment",
             "Secrets"
           ]
  end

  test "kind_from_tags maps environment tag to env_note" do
    assert VaultItemTags.kind_from_tags(["Environment"]) == "env_note"
    assert VaultItemTags.kind_from_tags(["Notes"]) == "generic_note"
  end

  test "env_display_mode? respects tags and kind" do
    assert VaultItemTags.env_display_mode?(["Environment"], "generic_note")
    assert VaultItemTags.env_display_mode?([], "env_note")
    refute VaultItemTags.env_display_mode?([], "generic_note")
  end

  test "merge_frontmatter stores user tags but not system Linked" do
    fm =
      VaultItemTags.merge_frontmatter(
        %{"linked_relative_path" => ".env"},
        ["Linked", "Environment", "Secrets"]
      )

    assert fm["linked_relative_path"] == ".env"
    assert VaultItemTags.decode(fm["tags"]) == ["Environment", "Secrets"]
  end

  test "encode keeps Linked but merge_frontmatter strips it for persistence" do
    assert "Linked" in VaultItemTags.decode(VaultItemTags.encode(["Linked", "Notes"]))

    fm = VaultItemTags.merge_frontmatter(%{}, ["Linked", "Notes"])
    assert VaultItemTags.decode(fm["tags"]) == ["Notes"]
  end
end
