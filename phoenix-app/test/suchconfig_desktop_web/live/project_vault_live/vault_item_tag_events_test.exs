defmodule SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEventsTest do
  use SuchConfigDesktop.DataCase

  import SuchConfigDesktop.EnvManagerFixtures

  alias SuchConfigDesktop.ProjectVault
  alias SuchConfigDesktop.ProjectVault.LinkedFrontmatter
  alias SuchConfigDesktop.ProjectVault.VaultItemTags
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktopWeb.ProjectVaultLive.VaultItemTagEvents

  @password "tag-events-pw"

  setup context do
    if Map.get(context, :crdt_nif_required, false) and not Crdt.available?() do
      {:skip, "Rustler NIF not loaded"}
    else
      :ok
    end
  end

  defp socket(overrides \\ %{}) do
    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.ProjectVaultLive,
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            note_category: "generic_note",
            display_mode: :input,
            item_tags: [],
            vault_password: @password,
            selected_folder_id: nil
          },
          overrides
        )
    }
  end

  describe "add_item_tag/2" do
    test "adds normalized user tags" do
      {:noreply, updated} =
        VaultItemTagEvents.add_item_tag(%{"tag" => "  environment "}, socket())

      assert updated.assigns.item_tags == ["Environment"]
    end

    test "rejects system Linked tag from user input" do
      {:noreply, updated} =
        VaultItemTagEvents.add_item_tag(%{"tag" => "Linked"}, socket(%{item_tags: ["Notes"]}))

      assert updated.assigns.item_tags == ["Notes"]
    end

    test "Environment tag enables env display mode on generic notes" do
      {:noreply, updated} =
        VaultItemTagEvents.add_item_tag(%{"tag" => "Environment"}, socket())

      assert updated.assigns.item_tags == ["Environment"]
      assert updated.assigns.display_mode == :copy
    end
  end

  describe "load_item_tags/3" do
    @tag :crdt_nif_required
    test "defaults env vault items to display mode" do
      folder = project_folder_fixture()

      {:ok, item} =
        ProjectVault.save_vault_item(
          %{
            title: ".env",
            kind: "env_note",
            security_mode: "global_passkey",
            project_folder_id: folder.id,
            body: "API_KEY=1",
            frontmatter: VaultItemTags.merge_frontmatter(%{}, ["Environment"])
          },
          @password
        )

      updated = VaultItemTagEvents.load_item_tags(socket(), item, @password)

      assert updated.assigns.display_mode == :copy
      assert "Environment" in updated.assigns.item_tags
    end

    @tag :crdt_nif_required
    test "keeps non-env vault items in edit mode" do
      folder = project_folder_fixture()

      {:ok, item} =
        ProjectVault.save_vault_item(
          %{
            title: "notes.md",
            kind: "generic_note",
            security_mode: "global_passkey",
            project_folder_id: folder.id,
            body: "hello",
            frontmatter: %{}
          },
          @password
        )

      updated = VaultItemTagEvents.load_item_tags(socket(), item, @password)

      assert updated.assigns.display_mode == :input
    end
  end

  describe "frontmatter_for_save/2" do
    @tag :crdt_nif_required
    test "stores user tags and preserves linked sync keys" do
      folder = project_folder_fixture()

      {:ok, item} =
        ProjectVault.save_vault_item(
          %{
            title: ".env",
            kind: "env_note",
            security_mode: "global_passkey",
            project_folder_id: folder.id,
            body: "API_KEY=1",
            frontmatter:
              LinkedFrontmatter.import_bundle(".env", "API_KEY=1", 0)
              |> VaultItemTags.merge_frontmatter(["Environment"])
          },
          @password
        )

      socket =
        socket(%{
          selected_folder_id: folder.id,
          item_tags: ["Environment", "Linked", "Secrets"]
        })

      fm = VaultItemTagEvents.frontmatter_for_save(socket, item.id)

      assert fm["linked_relative_path"] == ".env"
      assert fm["linked_content_sha256"]
      assert VaultItemTags.decode(fm["tags"]) == ["Environment", "Secrets"]
      refute "Linked" in VaultItemTags.decode(fm["tags"])
    end
  end
end
