defmodule MastheadWeb.PublicController do
  use MastheadWeb, :controller

  alias Masthead.Content
  alias Masthead.Themes.Renderer

  plug :require_site

  def index(conn, _params) do
    site = conn.assigns.current_site
    all_pages = Content.list_published_pages(site.id)
    pages = nav_pages(site, all_pages)

    case Content.get_homepage_page(site) do
      nil ->
        posts = Content.list_published_posts(site.id)
        body = Renderer.render_index(%{site: site, posts: posts, pages: pages})
        send_themed(conn, body)

      page ->
        render_page_or_404(conn, page, pages)
    end
  end

  def show_post(conn, %{"slug" => slug}) do
    site = conn.assigns.current_site
    pages = nav_pages(site, Content.list_published_pages(site.id))
    posts = Content.list_published_posts(site.id)

    case Content.get_published_post_by_slug(site.id, slug) do
      nil ->
        body = Renderer.render_not_found(%{site: site, pages: pages, posts: posts})
        conn |> put_status(:not_found) |> send_themed(body)

      post ->
        body_html = Content.render_body(post.body, post.format)

        body =
          Renderer.render_post(%{
            site: site,
            post: post,
            body_html: body_html,
            pages: pages,
            posts: posts
          })

        send_themed(conn, body)
    end
  end

  def show_page(conn, %{"slug" => slug}) do
    site = conn.assigns.current_site
    pages = nav_pages(site, Content.list_published_pages(site.id))
    page = Content.get_published_page_by_slug(site.id, slug)
    render_page_or_404(conn, page, pages)
  end

  @doc "Public post search: `/search?q=...`."
  def search(conn, params) do
    site = conn.assigns.current_site
    pages = nav_pages(site, Content.list_published_pages(site.id))
    query = params["q"] || ""
    posts = Content.search_posts(site.id, query)
    body = Renderer.render_search(%{site: site, posts: posts, query: query, pages: pages})
    send_themed(conn, body)
  end

  defp render_page_or_404(conn, nil, pages) do
    site = conn.assigns.current_site
    posts = Content.list_published_posts(site.id)
    body = Renderer.render_not_found(%{site: site, pages: pages, posts: posts})
    conn |> put_status(:not_found) |> send_themed(body)
  end

  defp render_page_or_404(conn, %{format: "blog"} = page, pages) do
    site = conn.assigns.current_site
    posts = Content.list_published_posts(site.id)
    # The body of a blog page is treated as Markdown intro text shown above
    # the post list. Pass an empty body through harmlessly.
    body_html = Content.render_body(page.body, "markdown")

    body =
      Renderer.render_blog(%{
        site: site,
        page: page,
        posts: posts,
        body_html: body_html,
        pages: pages
      })

    send_themed(conn, body)
  end

  defp render_page_or_404(conn, page, pages) do
    site = conn.assigns.current_site
    posts = Content.list_published_posts(site.id)
    body_html = Content.render_body(page.body, page.format)

    body =
      Renderer.render_page(%{
        site: site,
        page: page,
        body_html: body_html,
        pages: pages,
        posts: posts
      })

    send_themed(conn, body)
  end

  # The nav excludes: the site's designated homepage (already reachable
  # via the brand link at `/`), and any page explicitly hidden from the
  # nav via its `show_in_nav` flag.
  defp nav_pages(site, pages) do
    Enum.reject(pages, fn p ->
      p.id == site.homepage_page_id or p.show_in_nav == false
    end)
  end

  defp require_site(conn, _opts) do
    case conn.assigns[:current_site] do
      nil ->
        conn |> Plug.Conn.send_resp(404, "site not found") |> halt()

      _ ->
        conn
    end
  end

  defp send_themed(conn, body) when is_binary(body) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(conn.status || 200, body)
  end
end
