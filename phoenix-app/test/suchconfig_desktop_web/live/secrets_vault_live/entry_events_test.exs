defmodule SuchConfigDesktopWeb.SecretsVaultLive.EntryEventsTest do
  use ExUnit.Case, async: true

  alias SuchConfigDesktopWeb.SecretsVaultLive.EntryEvents

  defp socket(overrides \\ %{}) do
    %Phoenix.LiveView.Socket{
      endpoint: SuchConfigDesktopWeb.Endpoint,
      view: SuchConfigDesktopWeb.SecretsVaultLive,
      assigns:
        Map.merge(
          %{
            __changed__: %{},
            flash: %{},
            item_kind: "password",
            show_secret: true
          },
          overrides
        )
    }
  end

  describe "set_new_entry_kind/2" do
    test "maps modal type to item kind and hides secret field" do
      {:noreply, updated} = EntryEvents.set_new_entry_kind(%{"type" => "ssh"}, socket())

      assert updated.assigns.item_kind == "ssh_key"
      assert updated.assigns.show_secret == false
    end

    test "supports api and secure note types" do
      {:noreply, api} = EntryEvents.set_new_entry_kind(%{"type" => "api"}, socket())
      assert api.assigns.item_kind == "api_key"

      {:noreply, note} = EntryEvents.set_new_entry_kind(%{"type" => "note"}, socket())
      assert note.assigns.item_kind == "secure_note"
    end

    test "login type normalizes to password kind" do
      {:noreply, updated} = EntryEvents.set_new_entry_kind(%{"type" => "login"}, socket())
      assert updated.assigns.item_kind == "password"
    end
  end
end
