defmodule SuchConfigDesktopWeb.SecretsVaultLive.ViewDataTest do
  use SuchConfigDesktop.DataCase

  alias SuchConfigDesktop.SecretsVault
  alias SuchConfigDesktop.Vault.Crdt
  alias SuchConfigDesktopWeb.SecretsVaultLive.ViewData

  @password "view-data-test-pw"

  setup context do
    if Map.get(context, :crdt_nif_required, false) and not Crdt.available?() do
      {:skip, "Rustler NIF not loaded"}
    else
      :ok
    end
  end

  defp socket(extra) do
    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.SecretsVaultLive,
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            items: [],
            folders: SecretsVault.list_folders(),
            filter_types: [],
            filter_tags: [],
            filter_panel_query: "",
            selected_folder_id: nil,
            global_passkey_unlocked: true,
            vault_password: @password,
            item_tags: [],
            crdt_enabled?: Crdt.available?(),
            embedded: false,
            all_items: ViewData.not_loaded()
          },
          extra
        )
    }
  end

  @tag :crdt_nif_required
  test "assign_view_data filters folder items and reuses cached all_items" do
    {:ok, folder} = SecretsVault.ensure_unassociated_folder()

    {:ok, login} =
      SecretsVault.save_item(
        %{
          title: "Login item",
          kind: "password",
          secrets_vault_folder_id: folder.id,
          body: "secret",
          frontmatter: %{}
        },
        @password
      )

    {:ok, api} =
      SecretsVault.save_item(
        %{
          title: "API item",
          kind: "api_key",
          secrets_vault_folder_id: folder.id,
          body: "token",
          frontmatter: %{}
        },
        @password
      )

    items = SecretsVault.list_items(folder.id)

    s1 =
      socket(%{items: items, selected_folder_id: folder.id})
      |> ViewData.assign_view_data(refresh_all_items: true)

    assert length(s1.assigns.filtered_items) == 2
    cached_all_items = s1.assigns.all_items
    assert cached_all_items != []

    s2 =
      %{s1 | assigns: Map.put(s1.assigns, :filter_types, ["api"])}
      |> ViewData.assign_view_data()

    assert Enum.map(s2.assigns.filtered_items, & &1.id) == [api.id]
    assert s2.assigns.all_items == cached_all_items
    refute Enum.any?(s2.assigns.filtered_items, &(&1.id == login.id))
  end

  test "assign_view_data skips vault-wide query until load_all_items" do
    {:ok, folder} = SecretsVault.ensure_unassociated_folder()
    items = SecretsVault.list_items(folder.id)

    socket =
      socket(%{items: items, selected_folder_id: folder.id})
      |> ViewData.assign_view_data()

    assert socket.assigns.all_items == ViewData.not_loaded()
    assert socket.assigns.vault_stats.total == length(items)

    loaded =
      ViewData.assign_view_data(socket, load_all_items: true)

    assert is_list(loaded.assigns.all_items)
    assert loaded.assigns.vault_stats.total >= length(items)
  end

  @tag :crdt_nif_required
  test "assign_view_data refresh_all_items reloads vault-wide stats source" do
    {:ok, folder} = SecretsVault.ensure_unassociated_folder()

    {:ok, _} =
      SecretsVault.save_item(
        %{
          title: "Stats seed",
          kind: "secure_note",
          secrets_vault_folder_id: folder.id,
          body: "note",
          frontmatter: %{}
        },
        @password
      )

    s1 =
      socket(%{items: [], selected_folder_id: folder.id})
      |> ViewData.assign_view_data(refresh_all_items: true)

    assert s1.assigns.vault_stats.total >= 1

    {:ok, _} =
      SecretsVault.save_item(
        %{
          title: "Stats seed 2",
          kind: "secure_note",
          secrets_vault_folder_id: folder.id,
          body: "note2",
          frontmatter: %{}
        },
        @password
      )

    s2 =
      %{s1 | assigns: Map.put(s1.assigns, :items, SecretsVault.list_items(folder.id))}
      |> ViewData.assign_view_data()

    assert s2.assigns.vault_stats.total == s1.assigns.vault_stats.total

    s3 = ViewData.assign_view_data(s2, refresh_all_items: true)
    assert s3.assigns.vault_stats.total > s2.assigns.vault_stats.total
  end
end
