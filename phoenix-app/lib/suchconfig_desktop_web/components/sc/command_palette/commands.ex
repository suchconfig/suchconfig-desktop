defmodule SuchConfigDesktopWeb.Sc.CommandPalette.Commands do
  @moduledoc false

  @type item :: %{
          id: String.t(),
          icon: String.t(),
          label: String.t(),
          hint: String.t()
        }

  @type group :: %{group: String.t(), items: [item()]}

  @chord_actions %{
    "g" => %{
      "d" => "nav.dash",
      "w" => "nav.projects",
      "p" => "nav.proj",
      "s" => "nav.sec",
      "g" => "nav.gen",
      "," => "nav.settings",
      "e" => "export",
      "i" => "import"
    },
    "n" => %{
      "l" => "new.login",
      "a" => "new.api",
      "s" => "new.ssh",
      "n" => "new.note",
      "p" => "new.proj"
    }
  }

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
            %{id: "nav.gen", icon: "wand", label: "Password Generator", hint: "G then G"}
          ]
      else
        navigate
      end

    navigate =
      navigate ++
        [
          %{id: "nav.docs", icon: "book-open", label: "Open Docs", hint: ""},
          %{id: "nav.settings", icon: "gear", label: "Open Settings", hint: "G then ,"}
        ]

    create =
      if secrets_vault_enabled? do
        [
          %{id: "new.login", icon: "user", label: "New login entry", hint: "N then L"},
          %{id: "new.api", icon: "code", label: "New API key", hint: "N then A"},
          %{id: "new.ssh", icon: "ssh", label: "New SSH key", hint: "N then S"},
          %{id: "new.note", icon: "note", label: "New secure note", hint: "N then N"},
          %{id: "new.proj", icon: "folder", label: "New project", hint: "N then P"}
        ]
      else
        [%{id: "new.proj", icon: "folder", label: "New project", hint: "N then P"}]
      end

    [
      %{group: "Navigate", items: navigate},
      %{group: "Create", items: create},
      %{
        group: "Vault",
        items: [
          %{id: "lock", icon: "lock", label: "Lock vault now", hint: "⌃⇧L"},
          %{id: "import", icon: "chev-d", label: "Import sealed archive", hint: "G then I"},
          %{id: "export", icon: "archive", label: "Export sealed archive", hint: "G then E"}
        ]
      }
    ]
  end

  def flat_items(groups) do
    Enum.flat_map(groups, & &1.items)
  end

  def chord_action(prefix, key) when is_binary(prefix) and is_binary(key) do
    case Map.get(@chord_actions, String.downcase(prefix)) do
      %{} = map -> Map.get(map, String.downcase(key))
      _ -> nil
    end
  end

  def chord_action(_, _), do: nil

  def chord_prefixes, do: Map.keys(@chord_actions)

  def valid_command_id?(id, secrets_vault_enabled?) when is_binary(id) do
    groups(secrets_vault_enabled?)
    |> flat_items()
    |> Enum.any?(&(&1.id == id))
  end

  def valid_command_id?(_, _), do: false
end
