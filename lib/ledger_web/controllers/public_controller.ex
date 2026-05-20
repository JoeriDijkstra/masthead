defmodule LedgerWeb.PublicController do
  use LedgerWeb, :controller

  alias Ledger.{Content, Themes}

  plug :require_site

  def index(conn, _params) do
    site = conn.assigns.current_site
    all_pages = Content.list_published_pages(site.id)
    pages = nav_pages(site, all_pages)

    case Content.get_homepage_page(site) do
      nil ->
        posts = Content.list_published_posts(site.id)
        render_theme(conn, :render_index, %{site: site, posts: posts, pages: pages})

      page ->
        render_page_or_404(conn, page, pages)
    end
  end

  def show_post(conn, %{"slug" => slug}) do
    site = conn.assigns.current_site
    pages = nav_pages(site, Content.list_published_pages(site.id))

    case Content.get_published_post_by_slug(site.id, slug) do
      nil ->
        conn
        |> put_status(:not_found)
        |> render_theme(:render_not_found, %{site: site, pages: pages})

      post ->
        body_html = Content.render_body(post.body, post.format)

        render_theme(conn, :render_post, %{
          site: site,
          post: post,
          body_html: body_html,
          pages: pages
        })
    end
  end

  def show_page(conn, %{"slug" => slug}) do
    site = conn.assigns.current_site
    pages = nav_pages(site, Content.list_published_pages(site.id))
    page = Content.get_published_page_by_slug(site.id, slug)
    render_page_or_404(conn, page, pages)
  end

  defp render_page_or_404(conn, nil, pages) do
    site = conn.assigns.current_site

    conn
    |> put_status(:not_found)
    |> render_theme(:render_not_found, %{site: site, pages: pages})
  end

  defp render_page_or_404(conn, %{format: "blog"} = page, pages) do
    site = conn.assigns.current_site
    posts = Content.list_published_posts(site.id)
    # The body of a blog page is treated as Markdown intro text shown above
    # the post list. Pass an empty body through harmlessly.
    body_html = Content.render_body(page.body, "markdown")

    render_theme(conn, :render_blog, %{
      site: site,
      page: page,
      posts: posts,
      body_html: body_html,
      pages: pages
    })
  end

  defp render_page_or_404(conn, page, pages) do
    site = conn.assigns.current_site
    body_html = Content.render_body(page.body, page.format)

    render_theme(conn, :render_page, %{site: site, page: page, body_html: body_html, pages: pages})
  end

  # Hide the site's designated homepage page from the nav list — it's already
  # reachable via the brand link at `/`.
  defp nav_pages(site, pages) do
    Enum.reject(pages, &(&1.id == site.homepage_page_id))
  end

  defp require_site(conn, _opts) do
    case conn.assigns[:current_site] do
      nil ->
        conn |> Plug.Conn.send_resp(404, "site not found") |> halt()

      _ ->
        conn
    end
  end

  defp render_theme(conn, fun, assigns) do
    theme = Themes.get(conn.assigns.current_site.theme)
    rendered = apply(theme, fun, [assigns])
    iodata = Phoenix.HTML.Safe.to_iodata(rendered)

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(conn.status || 200, IO.iodata_to_binary(iodata))
  end
end
