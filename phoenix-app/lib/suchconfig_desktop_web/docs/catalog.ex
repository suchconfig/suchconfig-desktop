defmodule SuchConfigDesktopWeb.Docs.Catalog do
  @moduledoc false

  @categories [
    %{
      id: "vision",
      label: "Vision",
      articles: [
        %{
          id: "vision",
          label: "Why SuchConfig",
          summary: "Local-first vault for developers who own their data"
        }
      ]
    },
    %{
      id: "vaults",
      label: "Vaults",
      articles: [
        %{
          id: "project-vault",
          label: "Project Vault",
          summary: "Project folders, secure notes, and archives"
        },
        %{
          id: "secrets-vault",
          label: "Secrets Vault",
          summary: "Passwords, API keys, and credentials"
        }
      ]
    },
    %{
      id: "sync-backup",
      label: "Sync & backup",
      articles: [
        %{
          id: "trusted-folder",
          label: "Trusted Folder",
          summary: "Encrypted backups to a folder you control"
        },
        %{
          id: "wifi-p2p-sync",
          label: "WiFi P2P sync",
          summary: "Live sync between computers on the same Wi‑Fi"
        }
      ]
    },
    %{
      id: "tools",
      label: "Tools",
      articles: [
        %{
          id: "generator",
          label: "Generator",
          summary: "Local passwords, passphrases, and usernames"
        }
      ]
    }
  ]

  def categories, do: @categories

  def default_article_id, do: "vision"

  def article_ids do
    @categories
    |> Enum.flat_map(& &1.articles)
    |> Enum.map(& &1.id)
  end

  def find_article(id) when is_binary(id) do
    @categories
    |> Enum.flat_map(& &1.articles)
    |> Enum.find(&(&1.id == id))
  end

  def find_article(_), do: nil

  def normalize_article_id(id) when is_binary(id) do
    if id in article_ids(), do: id, else: default_article_id()
  end

  def normalize_article_id(_), do: default_article_id()
end
