defmodule SuchConfigDesktopWeb.Sc.CommandPalette.Commands do
  @moduledoc false

  @type item :: %{
          id: String.t(),
          icon: String.t(),
          label: String.t(),
          hint: String.t()
        }

  @type group :: %{group: String.t(), items: [item()]}

  def groups(secrets_vault_enabled?) do
    navigate = [
      %{id: "nav.dash", icon: "home", label: "Open Dashboard", hint: "G then D"},
      %{id: "nav.projects", icon: "folder", label: "Open Projects", hint: "G then W"},
      %{id: "nav.proj", icon: "vault", label: "Open Project Vault", hint: "G then P"}
    ]

    navigate =
      if secrets_vault_enabled? do
        navigate ++
          [
            %{id: "nav.sec", icon: "key", label: "Open Secrets Vault", hint: "G then S"},
            %{id: "nav.gen", icon: "wand", label: "Open Password Generator", hint: "G then G"}
          ]
      else
        navigate
      end

    navigate = navigate ++ [%{id: "nav.docs", icon: "book-open", label: "Open Docs", hint: ""}]

    [
      %{group: "Navigate", items: navigate},
      %{
        group: "Create",
        items: [
          %{id: "new.login", icon: "user", label: "New login entry", hint: "N then L"},
          %{id: "new.api", icon: "code", label: "New API key", hint: "N then A"},
          %{id: "new.ssh", icon: "ssh", label: "New SSH key", hint: "N then S"},
          %{id: "new.note", icon: "note", label: "New secure note", hint: "N then N"},
          %{id: "new.proj", icon: "folder", label: "New project folder", hint: "N then F"}
        ]
      },
      %{
        group: "Vault",
        items: [
          %{id: "lock", icon: "lock", label: "Lock vault now", hint: "⌃ ⇧ L"},
          %{id: "import", icon: "chev-d", label: "Import from .1pux / .csv", hint: ""},
          %{id: "export", icon: "archive", label: "Export sealed archive", hint: ""}
        ]
      }
    ]
  end

  def filter(groups, query) when is_binary(query) do
    q = String.trim(query) |> String.downcase()

    if q == "" do
      groups
    else
      groups
      |> Enum.map(fn %{group: group, items: items} ->
        %{group: group, items: Enum.filter(items, &matches?(&1, q))}
      end)
      |> Enum.reject(&Enum.empty?(&1.items))
    end
  end

  def flat_items(groups) do
    Enum.flat_map(groups, & &1.items)
  end

  defp matches?(%{label: label}, q), do: String.contains?(String.downcase(label), q)
end
