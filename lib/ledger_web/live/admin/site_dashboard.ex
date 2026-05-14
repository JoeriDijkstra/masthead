defmodule LedgerWeb.AdminLive.SiteDashboard do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.Content

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site
    posts = Content.list_posts(site.id)
    pages = Content.list_pages(site.id)

    {:ok,
     assign(socket,
       posts: posts,
       pages: pages,
       page_title: site.name
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title={@site.name} site={@site} current_user={@current_user} flash={@flash} active={:overview}>
      <:actions>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary">+ New post</.link>
      </:actions>

      <section class="stats">
        <div class="stat"><span class="num">{length(@posts)}</span> posts</div>
        <div class="stat"><span class="num">{Enum.count(@posts, & &1.published)}</span> published</div>
        <div class="stat"><span class="num">{length(@pages)}</span> pages</div>
      </section>

      <h2 class="section-heading">Recent posts</h2>

      <div :if={@posts == []} class="empty-state empty-state-illustrated">
        <img src={~p"/images/illustrations/empty-posts.svg"} alt="" class="empty-illustration" />
        <h2>No posts yet</h2>
        <p>Create your first post to start publishing. Drafts remain private until you publish them.</p>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary">+ New post</.link>
      </div>

      <ul :if={@posts != []} class="recent-list">
        <li :for={p <- Enum.take(@posts, 5)}>
          <.link navigate={~p"/#{@site.slug}/posts/#{p.id}/edit"}>
            <strong>{p.title}</strong>
            <span class={"pill pill-" <> if(p.published, do: "live", else: "draft")}>{if p.published, do: "Published", else: "Draft"}</span>
          </.link>
        </li>
      </ul>

      <p :if={length(@posts) > 5}>
        <.link navigate={~p"/#{@site.slug}/posts"}>See all posts &rarr;</.link>
      </p>
    </.shell>
    """
  end
end
