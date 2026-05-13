defmodule Ledger.Themes.Default do
  @moduledoc """
  The default theme. Minimal, readable, opinionated about typography.

  Designed to look fine on its own without Tailwind — public pages do not
  pull in the admin asset bundle.
  """
  use Phoenix.Component
  @behaviour Ledger.Themes.Theme

  @impl true
  def render_index(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <header class="site-header">
        <h1>{@site.title || @site.name}</h1>
        <p :if={@site.description != ""}>{@site.description}</p>
      </header>

      <section :if={@posts == []} class="empty">
        <p>No posts yet.</p>
      </section>

      <ul class="post-list" :if={@posts != []}>
        <li :for={post <- @posts}>
          <a href={"/posts/" <> post.slug}>
            <h2>{post.title}</h2>
            <p :if={post.excerpt != ""} class="excerpt">{post.excerpt}</p>
            <time :if={post.published_at} datetime={DateTime.to_iso8601(post.published_at)}>
              {Calendar.strftime(post.published_at, "%B %-d, %Y")}
            </time>
          </a>
        </li>
      </ul>
    </.layout>
    """
  end

  @impl true
  def render_post(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <article class="post">
        <header>
          <h1>{@post.title}</h1>
          <time :if={@post.published_at} datetime={DateTime.to_iso8601(@post.published_at)}>
            {Calendar.strftime(@post.published_at, "%B %-d, %Y")}
          </time>
        </header>
        <div class="post-body">
          {Phoenix.HTML.raw(@body_html)}
        </div>
        <footer><a href="/">&larr; Back to {@site.name}</a></footer>
      </article>
    </.layout>
    """
  end

  @impl true
  def render_page(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <article class="page">
        <div class="page-body">
          {Phoenix.HTML.raw(@body_html)}
        </div>
      </article>
    </.layout>
    """
  end

  @impl true
  def render_blog(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <header class="site-header">
        <h1>{@page.title}</h1>
      </header>

      <div :if={@body_html != ""} class="page-body">
        {Phoenix.HTML.raw(@body_html)}
      </div>

      <section :if={@posts == []} class="empty">
        <p>No posts yet.</p>
      </section>

      <ul class="post-list" :if={@posts != []}>
        <li :for={post <- @posts}>
          <a href={"/posts/" <> post.slug}>
            <h2>{post.title}</h2>
            <p :if={post.excerpt != ""} class="excerpt">{post.excerpt}</p>
            <time :if={post.published_at} datetime={DateTime.to_iso8601(post.published_at)}>
              {Calendar.strftime(post.published_at, "%B %-d, %Y")}
            </time>
          </a>
        </li>
      </ul>
    </.layout>
    """
  end

  @impl true
  def render_not_found(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <h1>Not found</h1>
      <p>That post or page doesn't exist.</p>
      <p><a href="/">&larr; Back to {@site.name}</a></p>
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
        <nav class="site-nav">
          <a class="brand" href="/">{@site.name}</a>
          <ul :if={@pages != []}>
            <li :for={p <- @pages}><a href={"/" <> p.slug}>{p.title}</a></li>
          </ul>
        </nav>
        <main>
          {render_slot(@inner_block)}
        </main>
        <footer class="site-footer">
          <p>Published with <a href="/">{@site.name}</a> on Ledger.</p>
        </footer>
      </body>
    </html>
    """
  end

  defp inline_styles do
    Phoenix.HTML.raw(["<style>", theme_css(), "</style>"])
  end

  def theme_css do
    """
    :root { --fg: #1a1a1a; --muted: #666; --accent: #0066cc; --bg: #fafafa; --rule: #e5e5e5; }
    *,*::before,*::after { box-sizing: border-box; }
    body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Inter", "Helvetica Neue", Arial, sans-serif; line-height: 1.6; color: var(--fg); background: var(--bg); }
    main, .site-nav, .site-footer { max-width: 720px; margin: 0 auto; padding: 0 1.25rem; }
    .site-nav { display: flex; align-items: center; justify-content: space-between; padding-top: 2rem; padding-bottom: 1.5rem; border-bottom: 1px solid var(--rule); }
    .site-nav .brand { font-weight: 600; text-decoration: none; color: var(--fg); }
    .site-nav ul { list-style: none; display: flex; gap: 1rem; margin: 0; padding: 0; }
    .site-nav a { color: var(--muted); text-decoration: none; }
    .site-nav a:hover { color: var(--fg); }
    main { padding-top: 2rem; padding-bottom: 4rem; }
    .site-header h1 { margin-bottom: 0.25rem; }
    .site-header p { color: var(--muted); margin-top: 0; }
    .post-list { list-style: none; padding: 0; margin: 2rem 0 0; }
    .post-list li { padding: 1.25rem 0; border-bottom: 1px solid var(--rule); }
    .post-list a { color: inherit; text-decoration: none; display: block; }
    .post-list h2 { margin: 0 0 0.25rem; font-size: 1.25rem; }
    .post-list .excerpt { margin: 0.25rem 0; color: var(--muted); }
    .post-list time { font-size: 0.85rem; color: var(--muted); }
    .post header { margin-bottom: 1.5rem; }
    .post header time { color: var(--muted); font-size: 0.9rem; }
    .post-body, .page-body { font-size: 1.05rem; }
    .post-body img, .page-body img { max-width: 100%; height: auto; }
    .post-body pre, .page-body pre { background: #fff; border: 1px solid var(--rule); padding: 0.75rem; overflow-x: auto; border-radius: 4px; }
    .post-body code, .page-body code { background: #fff; padding: 0.1em 0.3em; border: 1px solid var(--rule); border-radius: 3px; font-size: 0.9em; }
    .post-body pre code, .page-body pre code { border: 0; background: transparent; padding: 0; }
    .post-body a, .page-body a { color: var(--accent); }
    .post-body blockquote, .page-body blockquote { border-left: 3px solid var(--rule); margin: 1rem 0; padding: 0.1rem 1rem; color: var(--muted); }
    .empty { color: var(--muted); padding: 2rem 0; }
    .site-footer { margin-top: 4rem; padding-top: 1.5rem; border-top: 1px solid var(--rule); color: var(--muted); font-size: 0.85rem; }
    .post footer { margin-top: 2rem; }
    .post footer a, .empty a { color: var(--accent); text-decoration: none; }
    """
  end
end
