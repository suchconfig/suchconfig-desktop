defmodule SuchConfigDesktopWeb.SecretsVaultLiveTest do
  use SuchConfigDesktopWeb.ConnCase

  import Phoenix.LiveViewTest

  alias SuchConfigDesktop.{SecretsVault, Vault.Crdt, VaultSessionRegistry}

  @password "test-vault-password-placeholder"
  @live_opts [on_error: :warn]

  defp unlocked_secrets_conn(%{conn: conn}) do
    conn = get(conn, ~p"/secrets-vault")
    vault_session_id = Plug.Conn.get_session(conn, "vault_session_id")
    VaultSessionRegistry.put(vault_session_id, @password)
    {:ok, conn: conn, vault_session_id: vault_session_id}
  end

  describe "mount (locked)" do
    test "renders secrets vault page with unlock gate", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/secrets-vault", @live_opts)

      assert html =~ "Secrets Vault"
      assert has_element?(view, "#secrets-vault-root")
      assert has_element?(view, "#secrets-vault-unlock-button")
      refute has_element?(view, "#new-secret-button")
    end
  end

  describe "unlocked session" do
    setup context do
      if Map.get(context, :crdt_nif_required, false) and not Crdt.available?() do
        {:skip, "Rustler NIF not loaded"}
      else
        :ok
      end
    end

    setup [:unlocked_secrets_conn]

    test "shows sidebar and vault overview when no entry is selected", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/secrets-vault", @live_opts)

      refute html =~ "Unlock Global Passkey"
      assert has_element?(view, "#new-secret-button")
      assert has_element?(view, "#secrets-filter-button")
      assert has_element?(view, "#secrets-search-input")
      assert has_element?(view, "#secrets-folder-select")
      assert has_element?(view, "#new-secrets-folder-toolbar-button")
      assert has_element?(view, "#secrets-vault-stats")
      assert has_element?(view, "#secrets-page-stats-button")
      assert html =~ "Vault overview"
      refute has_element?(view, "#secrets-entry-detail")
      refute has_element?(view, "#save-secret-button")
      assert has_element?(view, "#lock-secrets-vault-button")
    end

    test "lists unassociated folder and entries after seeding", %{conn: conn} do
      {:ok, folder} = SecretsVault.ensure_unassociated_folder()

      if Crdt.available?() do
        {:ok, item} =
          SecretsVault.save_item(
            %{
              title: "Seeded login",
              kind: "password",
              secrets_vault_folder_id: folder.id,
              body: "placeholder",
              frontmatter: %{"username" => "seed@example.com"}
            },
            @password
          )

        {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

        assert has_element?(view, "#secrets-entry-#{item.id}")

        view
        |> element("#secrets-entry-#{item.id}")
        |> render_click()

        assert render(view) =~ "Seeded login"
        assert has_element?(view, "#secrets-entry-detail")
        assert has_element?(view, "#secret-title-input")
        assert has_element?(view, "#save-secret-button")
        assert has_element?(view, "#entry-detail-folder-select")
        assert has_element?(view, "#entry-detail-folder-button")
        assert has_element?(view, "#copy-secret-button[data-copy-event=copy_secret]")
        assert has_element?(view, "#copy-secret-button[data-copy-text=placeholder]")
        assert has_element?(view, "#copy-username-button[data-copy-text=\"seed@example.com\"]")
        refute has_element?(view, "#secrets-vault-stats")

        view |> element("#secrets-page-stats-button") |> render_click()

        assert has_element?(view, "#secrets-vault-stats")
        refute has_element?(view, "#secrets-entry-detail")
      end
    end

    test "creates a folder from the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)
      unique = "QA #{System.unique_integer([:positive])}"

      render_click(view, "open_new_folder_modal")

      assert has_element?(view, "#new-secrets-folder-modal")

      view
      |> form("#new-secrets-folder-form", %{
        "folder" => %{"name" => unique, "description" => "Test folder"}
      })
      |> render_submit()

      html = render(view)
      assert html =~ unique
      assert Enum.any?(SecretsVault.list_folders(), &(&1.name == unique))
    end

    test "deletes a folder from the edit modal", %{conn: conn} do
      unique = "Delete me #{System.unique_integer([:positive])}"
      {:ok, folder} = SecretsVault.create_folder(%{name: unique})

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      render_click(view, "open_edit_folder", %{"id" => "#{folder.id}"})

      assert has_element?(view, "#edit-secrets-folder-modal")
      assert has_element?(view, "#edit-secrets-folder-delete")

      view |> element("#edit-secrets-folder-delete") |> render_click()
      assert has_element?(view, "#edit-secrets-folder-delete-confirm")

      view |> element("#edit-secrets-folder-delete-confirm") |> render_click()

      refute has_element?(view, "#edit-secrets-folder-modal")
      assert render(view) =~ "Folder deleted."
      refute Enum.any?(SecretsVault.list_folders(), &(&1.id == folder.id))
    end

    @tag :crdt_nif_required
    test "creates and saves a new secret entry", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view |> element("#new-secret-button") |> render_click()
      assert has_element?(view, "#new-entry-modal")
      assert has_element?(view, "#new-entry-folder-select")
      assert has_element?(view, "#new-entry-folder-button")

      assert has_element?(view, "#new-entry-username-input")
      refute has_element?(view, "#new-entry-environment-input")

      view
      |> form("#new-entry-form", %{
        "title" => "LiveView test entry",
        "kind" => "password",
        "username" => "live@example.com",
        "url" => "https://example.com",
        "secret_body" => "placeholder-live-pw"
      })
      |> render_submit()

      html = render(view)
      assert html =~ "LiveView test entry"
      assert html =~ "Entry saved."
      refute has_element?(view, "#new-entry-modal")
      assert has_element?(view, "#secrets-entry-form")
      assert has_element?(view, "#secret-username-input[value=\"live@example.com\"]")
    end

    @tag :crdt_nif_required
    test "saves a new entry into the selected folder", %{conn: conn} do
      unique = "Folder #{System.unique_integer([:positive])}"
      {:ok, folder} = SecretsVault.create_folder(%{name: unique})

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      render_click(view, "select_folder", %{"id" => "#{folder.id}"})

      view |> element("#new-secret-button") |> render_click()
      assert has_element?(view, "#new-entry-modal")

      view
      |> form("#new-entry-form", %{
        "secrets_vault_folder_id" => "#{folder.id}",
        "title" => "Folder-scoped entry",
        "kind" => "password",
        "username" => "scoped@example.com",
        "secret_body" => "scoped-secret"
      })
      |> render_submit()

      assert has_element?(view, "#secrets-entry-list")
      assert render(view) =~ "Folder-scoped entry"
      assert render(view) =~ "Entry saved."

      saved = Enum.find(SecretsVault.list_items(folder.id), &(&1.title == "Folder-scoped entry"))
      assert saved
      assert saved.secrets_vault_folder_id == folder.id
    end

    test "folder toolbar switches visible entries", %{conn: conn} do
      unique = "Toolbar #{System.unique_integer([:positive])}"
      {:ok, folder} = SecretsVault.create_folder(%{name: unique})

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view
      |> form("#secrets-folder-toolbar-form", %{"folder_id" => "#{folder.id}"})
      |> render_change()

      html = render(view)
      assert html =~ unique
    end

    @tag :crdt_nif_required
    test "saves new entry to unassociated when folder not selected", %{conn: conn} do
      {:ok, unassociated} = SecretsVault.ensure_unassociated_folder()

      {:ok, other} =
        SecretsVault.create_folder(%{name: "Other #{System.unique_integer([:positive])}"})

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      render_click(view, "select_folder", %{"id" => "#{other.id}"})
      view |> element("#new-secret-button") |> render_click()

      view
      |> form("#new-entry-form", %{
        "secrets_vault_folder_id" => "",
        "title" => "Loose entry",
        "kind" => "password",
        "secret_body" => "loose-secret"
      })
      |> render_submit()

      assert render(view) =~ "Entry saved."
      saved = Enum.find(SecretsVault.list_items(unassociated.id), &(&1.title == "Loose entry"))
      assert saved
      assert saved.secrets_vault_folder_id == unassociated.id
    end

    @tag :crdt_nif_required
    test "search filters visible entries", %{conn: conn} do
      {:ok, folder} = SecretsVault.ensure_unassociated_folder()

      {:ok, visible} =
        SecretsVault.save_item(
          %{
            title: "VisibleBank",
            kind: "password",
            secrets_vault_folder_id: folder.id,
            body: "x",
            frontmatter: %{"username" => "visible@bank.com"}
          },
          @password
        )

      {:ok, _hidden} =
        SecretsVault.save_item(
          %{
            title: "OtherService",
            kind: "api_key",
            secrets_vault_folder_id: folder.id,
            body: "y",
            frontmatter: %{}
          },
          @password
        )

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view
      |> form("#secrets-search-form", %{"search" => "visible"})
      |> render_change()

      assert has_element?(view, "#secrets-entry-#{visible.id}")
      refute render(view) =~ "OtherService"
    end

    @tag :crdt_nif_required
    test "moves entry to another folder on save", %{conn: conn} do
      {:ok, source} = SecretsVault.ensure_unassociated_folder()
      target_name = "Move target #{System.unique_integer([:positive])}"
      {:ok, target} = SecretsVault.create_folder(%{name: target_name})

      {:ok, item} =
        SecretsVault.save_item(
          %{
            title: "Movable entry",
            kind: "password",
            secrets_vault_folder_id: source.id,
            body: "secret",
            frontmatter: %{}
          },
          @password
        )

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      render_click(view, "select_folder", %{"id" => "#{source.id}"})
      view |> element("#secrets-entry-#{item.id}") |> render_click()

      view
      |> form("#secrets-entry-form", %{
        "secrets_vault_folder_id" => "#{target.id}",
        "title" => "Movable entry"
      })
      |> render_submit()

      assert render(view) =~ "Entry saved."
      assert has_element?(view, "#secrets-entry-#{item.id}")

      saved = SecretsVault.get_item!(item.id)
      assert saved.secrets_vault_folder_id == target.id

      render_click(view, "select_folder", %{"id" => "#{source.id}"})
      refute has_element?(view, "#secrets-entry-#{item.id}")

      render_click(view, "select_folder", %{"id" => "#{target.id}"})
      assert has_element?(view, "#secrets-entry-#{item.id}")
    end

    @tag :crdt_nif_required
    test "adds tags from entry detail and persists on save", %{conn: conn} do
      alias SuchConfigDesktop.ProjectVault.VaultItemTags

      {:ok, folder} = SecretsVault.ensure_unassociated_folder()

      {:ok, item} =
        SecretsVault.save_item(
          %{
            title: "Tagged entry",
            kind: "password",
            secrets_vault_folder_id: folder.id,
            body: "secret",
            frontmatter: %{}
          },
          @password
        )

      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view |> element("#secrets-entry-#{item.id}") |> render_click()
      assert has_element?(view, "#secrets-entry-tag-picker")

      render_click(view, "add_item_tag", %{"tag" => "work"})
      assert render(view) =~ "Work"

      view
      |> form("#secrets-entry-form", %{"title" => "Tagged entry"})
      |> render_submit()

      assert render(view) =~ "Entry saved."

      {:ok, fm} =
        SecretsVault.decrypt_item_frontmatter(SecretsVault.get_item!(item.id), @password)

      assert "Work" in VaultItemTags.decode(Map.get(fm, "tags"))
    end

    test "opens password generator drawer", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view |> element("#new-secret-button") |> render_click()
      assert has_element?(view, "#new-entry-modal")
      view |> element("#new-entry-generate-button") |> render_click()

      assert has_element?(view, "#generator-drawer")
      assert has_element?(view, "#generator-output")
      assert has_element?(view, "#generator-roll-button")
    end

    test "new entry modal renders type picker hook and active entry panel only", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view |> element("#new-secret-button") |> render_click()

      html = render(view)
      assert html =~ ~s(phx-hook="NewEntryTypePicker")
      assert html =~ ~s(data-entry-type="login")
      assert has_element?(view, "#new-entry-username-input")
      refute has_element?(view, "#new-entry-environment-input")
      refute has_element?(view, "#new-entry-fingerprint-input")
      refute has_element?(view, "#new-entry-note-input")
    end

    test "set_new_entry_kind switches visible form fields", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/secrets-vault", @live_opts)

      view |> element("#new-secret-button") |> render_click()

      render_click(view, "set_new_entry_kind", %{"type" => "ssh"})
      html = render(view)

      assert html =~ ~s(name="kind" value="ssh_key")
      assert html =~ ~s(id="new-entry-type-ssh" class="type-card active")
      assert has_element?(view, "#new-entry-fingerprint-input")
      refute has_element?(view, "#new-entry-username-input")

      render_click(view, "set_new_entry_kind", %{"type" => "api"})
      html = render(view)

      assert html =~ ~s(name="kind" value="api_key")
      assert html =~ ~s(id="new-entry-type-api" class="type-card active")
      assert has_element?(view, "#new-entry-token-input")
      assert has_element?(view, "#new-entry-environment-input")
      refute has_element?(view, "#new-entry-fingerprint-input")
    end
  end
end
