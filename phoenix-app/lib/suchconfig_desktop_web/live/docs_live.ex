defmodule SuchConfigDesktopWeb.DocsLive do
  use SuchConfigDesktopWeb, :live_view

  alias SuchConfigDesktopWeb.Components.Docs.GeneratorGuide
  alias SuchConfigDesktopWeb.Components.Docs.ProjectVaultGuide
  alias SuchConfigDesktopWeb.Components.Docs.SecretsVaultGuide
  alias SuchConfigDesktopWeb.Components.Docs.TrustedFolderGuide
  alias SuchConfigDesktopWeb.Components.Docs.VisionGuide
  alias SuchConfigDesktopWeb.Components.Docs.WifiP2pSyncGuide
  alias SuchConfigDesktopWeb.Docs.Catalog

  @impl true
  def mount(params, _session, socket) do
    article_id = initial_article_id(params)

    {:ok,
     assign(socket,
       page_title: "Docs - SuchConfig Desktop",
       article_id: article_id,
       categories: Catalog.categories()
     )}
  end

  @impl true
  def handle_event("select_doc", %{"id" => id}, socket) do
    {:noreply, assign(socket, article_id: Catalog.normalize_article_id(id))}
  end

  def handle_event("select_doc", _params, socket), do: {:noreply, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <div id="docs-live-root" class="docs-shell">
      <nav class="docs-nav" aria-label="Documentation">
        <div class="docs-nav-head">
          <span>Guides</span>
        </div>
        <div :for={category <- @categories} class="docs-nav-category">
          <div class="docs-nav-category-label">{category.label}</div>
          <button
            :for={article <- category.articles}
            id={"docs-nav-#{article.id}"}
            type="button"
            class={["docs-nav-item", @article_id == article.id && "active"]}
            phx-click="select_doc"
            phx-value-id={article.id}
          >
            <span class="docs-nav-item-label">{article.label}</span>
            <span class="docs-nav-item-summary">{article.summary}</span>
          </button>
        </div>
        <p class="docs-nav-foot muted">
          More guides — recovery, imports, and advanced topics — will appear here. A hosted docs site is planned for extended reference.
        </p>
      </nav>
      <div class="docs-article">
        <VisionGuide.guide :if={@article_id == "vision"} />
        <GeneratorGuide.guide :if={@article_id == "generator"} />
        <ProjectVaultGuide.guide :if={@article_id == "project-vault"} />
        <SecretsVaultGuide.guide :if={@article_id == "secrets-vault"} />
        <TrustedFolderGuide.guide :if={@article_id == "trusted-folder"} />
        <WifiP2pSyncGuide.guide :if={@article_id == "wifi-p2p-sync"} />
      </div>
    </div>
    """
  end

  defp initial_article_id(%{"article" => article}), do: Catalog.normalize_article_id(article)
  defp initial_article_id(_), do: Catalog.default_article_id()
end
