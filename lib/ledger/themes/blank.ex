defmodule Ledger.Themes.Blank do
  @moduledoc """
  Blank theme — designed to get out of the way completely so you can
  hand-craft HTML pages with their own structure. Full-width main
  content, no header, no footer, no menu bar. Just a basic CSS reset
  and your HTML.

  Pick this theme when you want to write HTML pages where your own
  markup defines the entire layout including any navigation.
  """
  use Phoenix.Component
  @behaviour Ledger.Themes.Theme

  @impl true
  def render_index(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="default-index">
        <h1>{@site.title || @site.name}</h1>
        <p :if={@site.description != ""}>{@site.description}</p>

        <ul :if={@posts != []}>
          <li :for={post <- @posts}>
            <a href={"/posts/" <> post.slug}>{post.title}</a>
            <time :if={post.published_at}>
              {Calendar.strftime(post.published_at, "%Y-%m-%d")}
            </time>
          </li>
        </ul>

        <p :if={@posts == []}>No posts yet.</p>
      </section>
    </.layout>
    """
  end

  @impl true
  def render_post(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <article class="default-post">
        <header>
          <h1>{@post.title}</h1>
          <time :if={@post.published_at} datetime={DateTime.to_iso8601(@post.published_at)}>
            {Calendar.strftime(@post.published_at, "%B %-d, %Y")}
          </time>
        </header>
        {Phoenix.HTML.raw(@body_html)}
      </article>
    </.layout>
    """
  end

  @impl true
  def render_page(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      {Phoenix.HTML.raw(@body_html)}
    </.layout>
    """
  end

  @impl true
  def render_blog(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="default-index">
        <h1>{@page.title}</h1>
        <div :if={@body_html != ""}>{Phoenix.HTML.raw(@body_html)}</div>

        <ul :if={@posts != []}>
          <li :for={post <- @posts}>
            <a href={"/posts/" <> post.slug}>{post.title}</a>
            <time :if={post.published_at}>
              {Calendar.strftime(post.published_at, "%Y-%m-%d")}
            </time>
          </li>
        </ul>

        <p :if={@posts == []}>No posts yet.</p>
      </section>
    </.layout>
    """
  end

  @impl true
  def render_not_found(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="default-index">
        <h1>Not found</h1>
        <p>That post or page doesn't exist.</p>
      </section>
    </.layout>
    """
  end

  attr :site, :map, required: true
  attr :pages, :list, default: []
  slot :inner_block, required: true

  defp layout(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@site.title || @site.name}</title>
        <meta :if={@site.description != ""} name="description" content={@site.description} />
        {inline_styles()}
      </head>
      <body>
        <main class="content">
          {render_slot(@inner_block)}
        </main>
      </body>
    </html>
    """
  end

  defp inline_styles do
    Phoenix.HTML.raw(["<style>", theme_css(), "</style>"])
  end

  def theme_css do
    """
    *, *::before, *::after { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      font-family: -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      color: #111;
      background: #fff;
      line-height: 1.5;
      -webkit-font-smoothing: antialiased;
    }
    main { flex: 1; width: 100%; }
    a { color: #0066cc; }
    img { max-width: 100%; height: auto; }

    /* Content is full-width, zero padding — your HTML defines its own layout */
    .content { width: 100%; }

    /* Modest styling for the built-in fallback views (index / post / 404 /
       blog) so they're readable without looking unstyled. HTML and Markdown
       pages do not get these — they render raw inside .content. */
    .default-index, .default-post {
      max-width: 720px;
      margin: 0 auto;
      padding: 2rem 1.25rem;
    }
    .default-index ul { list-style: none; padding: 0; margin: 1.5rem 0 0; }
    .default-index li {
      padding: 0.6rem 0;
      border-bottom: 1px solid #eee;
      display: flex;
      justify-content: space-between;
      gap: 1rem;
    }
    .default-index li time { color: #888; font-size: 0.85rem; white-space: nowrap; }
    .default-post header { margin-bottom: 1.5rem; }
    .default-post header time { color: #888; font-size: 0.9rem; }

    @media (max-width: 640px) {
      .default-index, .default-post { padding: 1.5rem 1rem; }
    }
    """
  end
end
