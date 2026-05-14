defmodule Ledger.Themes.Studio do
  @moduledoc """
  Studio theme — mirrors the design language of the Ledger admin: blue
  accent, soft cards on a near-white background, generous whitespace,
  rounded corners, system font stack. Built for editorial reading.
  """
  use Phoenix.Component
  @behaviour Ledger.Themes.Theme

  @impl true
  def render_index(assigns) do
    {featured, rest} = Enum.split(assigns.posts, 1)
    assigns = Map.merge(assigns, %{featured: List.first(featured), rest: rest})

    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="hero">
        <p class="eyebrow">{@site.name}</p>
        <h1>{@site.title || @site.name}</h1>
        <p :if={@site.description != ""} class="lede">{@site.description}</p>
      </section>

      <section :if={@posts == []} class="empty-state">
        <p>No posts yet. Check back soon.</p>
      </section>

      <section :if={@featured} class="featured">
        <a href={"/posts/" <> @featured.slug} class="featured-card">
          <span class="card-eyebrow">Latest</span>
          <h2>{@featured.title}</h2>
          <p :if={@featured.excerpt != ""} class="featured-excerpt">{@featured.excerpt}</p>
          <div class="meta">
            <time :if={@featured.published_at} datetime={DateTime.to_iso8601(@featured.published_at)}>
              {Calendar.strftime(@featured.published_at, "%b %-d, %Y")}
            </time>
            <span class="read-more">Read &rarr;</span>
          </div>
        </a>
      </section>

      <section :if={@rest != []} class="archive">
        <h2 class="section-title">More writing</h2>
        <ul class="post-grid">
          <li :for={p <- @rest}>
            <a href={"/posts/" <> p.slug} class="post-card">
              <h3>{p.title}</h3>
              <p :if={p.excerpt != ""} class="excerpt">{p.excerpt}</p>
              <time :if={p.published_at} datetime={DateTime.to_iso8601(p.published_at)}>
                {Calendar.strftime(p.published_at, "%b %-d, %Y")}
              </time>
            </a>
          </li>
        </ul>
      </section>
    </.layout>
    """
  end

  @impl true
  def render_post(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <article class="post">
        <header class="post-header">
          <p class="eyebrow">
            <a href="/">{@site.name}</a>
            <span class="dot">·</span>
            <time :if={@post.published_at} datetime={DateTime.to_iso8601(@post.published_at)}>
              {Calendar.strftime(@post.published_at, "%B %-d, %Y")}
            </time>
          </p>
          <h1>{@post.title}</h1>
          <p :if={@post.excerpt != ""} class="lede">{@post.excerpt}</p>
        </header>

        <div class="prose">
          {Phoenix.HTML.raw(@body_html)}
        </div>

        <footer class="post-footer">
          <a href="/" class="back-link">&larr; Back to {@site.name}</a>
        </footer>
      </article>
    </.layout>
    """
  end

  @impl true
  def render_page(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <article class="page">
        <div class="prose">
          {Phoenix.HTML.raw(@body_html)}
        </div>
      </article>
    </.layout>
    """
  end

  @impl true
  def render_blog(assigns) do
    assigns = Map.merge(assigns, %{has_intro: assigns.body_html != ""})

    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="hero">
        <p class="eyebrow">Writing</p>
        <h1>{@page.title}</h1>
      </section>

      <div :if={@has_intro} class="prose blog-intro">
        {Phoenix.HTML.raw(@body_html)}
      </div>

      <section :if={@posts == []} class="empty-state">
        <p>No posts yet.</p>
      </section>

      <section :if={@posts != []} class="archive">
        <h2 class="section-title">All posts</h2>
        <ul class="post-grid">
          <li :for={p <- @posts}>
            <a href={"/posts/" <> p.slug} class="post-card">
              <h3>{p.title}</h3>
              <p :if={p.excerpt != ""} class="excerpt">{p.excerpt}</p>
              <time :if={p.published_at} datetime={DateTime.to_iso8601(p.published_at)}>
                {Calendar.strftime(p.published_at, "%b %-d, %Y")}
              </time>
            </a>
          </li>
        </ul>
      </section>
    </.layout>
    """
  end

  @impl true
  def render_not_found(assigns) do
    ~H"""
    <.layout site={@site} pages={@pages}>
      <section class="not-found">
        <p class="eyebrow">404</p>
        <h1>Page not found</h1>
        <p class="lede">That post or page doesn't exist on {@site.name}.</p>
        <p><a class="btn" href="/">&larr; Back home</a></p>
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
        <link rel="preconnect" href="https://rsms.me/" />
        <link rel="stylesheet" href="https://rsms.me/inter/inter.css" />
        {inline_styles()}
      </head>
      <body>
        <header class="site-header">
          <div class="container nav">
            <a class="brand" href="/">
              <span class="brand-mark">●</span>
              <span class="brand-name">{@site.name}</span>
            </a>
            <nav :if={@pages != []} class="primary-nav">
              <a :for={p <- @pages} href={"/" <> p.slug}>{p.title}</a>
            </nav>
          </div>
        </header>

        <main class="content">
          <div class="container">
            {render_slot(@inner_block)}
          </div>
        </main>

        <footer class="site-footer">
          <div class="container">
            <p class="muted">
              Published with
              <a href="https://ledger-cloud.com" target="_blank" rel="noopener">Ledger</a>
            </p>
          </div>
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
    :root {
      --fg: #0f172a;
      --fg-soft: #334155;
      --muted: #64748b;
      --rule: #e2e8f0;
      --rule-strong: #cbd5e1;
      --bg: #f8fafc;
      --card: #ffffff;
      --accent: #2563eb;
      --accent-hover: #1d4ed8;
      --accent-soft: #eff6ff;
      --shadow-sm: 0 1px 2px rgba(15, 23, 42, 0.04);
      --shadow-md: 0 4px 14px rgba(15, 23, 42, 0.06);
      --shadow-lg: 0 12px 32px rgba(15, 23, 42, 0.08);
    }

    *, *::before, *::after { box-sizing: border-box; }
    html { -webkit-text-size-adjust: 100%; }
    body {
      margin: 0;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      font-family: "Inter", -apple-system, BlinkMacSystemFont, "Helvetica Neue", Arial, sans-serif;
      color: var(--fg);
      background: var(--bg);
      line-height: 1.6;
      -webkit-font-smoothing: antialiased;
      font-feature-settings: "ss01", "cv11";
    }
    main { flex: 1; width: 100%; }
    a { color: var(--accent); text-decoration: none; transition: color 0.15s ease; }
    a:hover { color: var(--accent-hover); }

    .container { max-width: 880px; margin: 0 auto; padding: 0 1.5rem; width: 100%; }
    .muted { color: var(--muted); }

    /* Header */
    .site-header {
      background: var(--card);
      border-bottom: 1px solid var(--rule);
      position: sticky;
      top: 0;
      z-index: 10;
      backdrop-filter: saturate(180%) blur(8px);
      background: rgba(255, 255, 255, 0.85);
    }
    .nav {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding-top: 1.1rem;
      padding-bottom: 1.1rem;
    }
    .brand {
      display: inline-flex;
      align-items: center;
      gap: 0.55rem;
      color: var(--fg);
      font-weight: 600;
      font-size: 0.95rem;
      letter-spacing: -0.01em;
    }
    .brand:hover { color: var(--fg); }
    .brand-mark { color: var(--accent); font-size: 0.85rem; }
    .primary-nav { display: flex; gap: 1.5rem; }
    .primary-nav a {
      color: var(--muted);
      font-size: 0.92rem;
      font-weight: 500;
    }
    .primary-nav a:hover { color: var(--fg); }

    /* Content */
    .content { padding-top: 3rem; padding-bottom: 4rem; }

    /* Eyebrows / small labels */
    .eyebrow {
      font-size: 0.78rem;
      font-weight: 600;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--accent);
      margin: 0 0 0.75rem;
    }
    .eyebrow a { color: var(--accent); }
    .eyebrow .dot { margin: 0 0.4rem; color: var(--muted); }
    .eyebrow time { color: var(--muted); font-weight: 500; text-transform: none; letter-spacing: 0; }

    /* Hero (index) */
    .hero { margin-bottom: 3rem; }
    .hero h1 {
      font-size: clamp(2rem, 4vw, 2.6rem);
      letter-spacing: -0.025em;
      line-height: 1.15;
      margin: 0 0 0.75rem;
      color: var(--fg);
    }
    .lede {
      font-size: 1.15rem;
      color: var(--fg-soft);
      line-height: 1.6;
      max-width: 60ch;
      margin: 0;
    }

    /* Featured card */
    .featured-card {
      display: block;
      background: var(--card);
      border: 1px solid var(--rule);
      border-radius: 14px;
      padding: 1.75rem;
      box-shadow: var(--shadow-sm);
      transition: transform 0.18s ease, box-shadow 0.18s ease, border-color 0.18s ease;
      color: inherit;
      margin-bottom: 3rem;
    }
    .featured-card:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-md);
      border-color: var(--rule-strong);
      color: inherit;
    }
    .card-eyebrow {
      display: inline-block;
      background: var(--accent-soft);
      color: var(--accent);
      padding: 0.2rem 0.6rem;
      border-radius: 999px;
      font-size: 0.72rem;
      font-weight: 600;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      margin-bottom: 0.9rem;
    }
    .featured-card h2 {
      font-size: 1.55rem;
      line-height: 1.25;
      letter-spacing: -0.015em;
      margin: 0 0 0.6rem;
    }
    .featured-excerpt {
      color: var(--fg-soft);
      margin: 0 0 1.2rem;
      line-height: 1.55;
    }
    .featured-card .meta {
      display: flex;
      align-items: center;
      justify-content: space-between;
      font-size: 0.88rem;
      color: var(--muted);
    }
    .read-more { color: var(--accent); font-weight: 500; }

    /* Archive grid */
    .section-title {
      font-size: 0.78rem;
      font-weight: 600;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
      margin: 0 0 1rem;
      padding-bottom: 0.7rem;
      border-bottom: 1px solid var(--rule);
    }
    .post-grid {
      list-style: none;
      padding: 0;
      margin: 0;
      display: grid;
      grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
      gap: 1rem;
    }
    .post-card {
      display: block;
      background: var(--card);
      border: 1px solid var(--rule);
      border-radius: 12px;
      padding: 1.25rem;
      color: inherit;
      transition: transform 0.18s ease, box-shadow 0.18s ease, border-color 0.18s ease;
      height: 100%;
    }
    .post-card:hover {
      transform: translateY(-2px);
      box-shadow: var(--shadow-md);
      border-color: var(--rule-strong);
      color: inherit;
    }
    .post-card h3 {
      font-size: 1.1rem;
      line-height: 1.3;
      letter-spacing: -0.01em;
      margin: 0 0 0.5rem;
    }
    .post-card .excerpt {
      font-size: 0.92rem;
      color: var(--fg-soft);
      margin: 0 0 0.8rem;
      line-height: 1.55;
      display: -webkit-box;
      -webkit-line-clamp: 3;
      -webkit-box-orient: vertical;
      overflow: hidden;
    }
    .post-card time { font-size: 0.82rem; color: var(--muted); }

    /* Single post / page */
    .post-header, .page-header { margin-bottom: 2.5rem; }
    .post-header h1, .page-header h1 {
      font-size: clamp(1.9rem, 3.5vw, 2.4rem);
      line-height: 1.2;
      letter-spacing: -0.02em;
      margin: 0 0 0.85rem;
    }

    /* Prose (rendered markdown) */
    .prose {
      font-size: 1.075rem;
      line-height: 1.75;
      color: var(--fg);
    }
    .prose > *:first-child { margin-top: 0; }
    .prose h1, .prose h2, .prose h3, .prose h4 {
      letter-spacing: -0.015em;
      line-height: 1.3;
      margin-top: 2.25rem;
      margin-bottom: 0.75rem;
    }
    .prose h2 { font-size: 1.45rem; }
    .prose h3 { font-size: 1.2rem; }
    .prose p { margin: 0 0 1.15rem; }
    .prose a { color: var(--accent); text-decoration: underline; text-decoration-color: var(--accent-soft); text-decoration-thickness: 2px; text-underline-offset: 3px; }
    .prose a:hover { text-decoration-color: var(--accent); }
    .prose ul, .prose ol { padding-left: 1.4rem; margin: 0 0 1.15rem; }
    .prose li { margin-bottom: 0.35rem; }
    .prose blockquote {
      border-left: 3px solid var(--accent);
      padding: 0.2rem 0 0.2rem 1.25rem;
      margin: 1.5rem 0;
      color: var(--fg-soft);
      font-style: italic;
      background: var(--accent-soft);
      border-radius: 0 6px 6px 0;
    }
    .prose code {
      font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
      font-size: 0.88em;
      background: #f1f5f9;
      padding: 0.15em 0.4em;
      border-radius: 4px;
      color: var(--fg);
    }
    .prose pre {
      background: #0f172a;
      color: #e2e8f0;
      padding: 1.1rem 1.25rem;
      border-radius: 10px;
      overflow-x: auto;
      font-size: 0.9rem;
      line-height: 1.6;
      margin: 1.5rem 0;
    }
    .prose pre code {
      background: transparent;
      padding: 0;
      color: inherit;
      font-size: 1em;
    }
    .prose img {
      max-width: 100%;
      height: auto;
      border-radius: 10px;
      margin: 1.5rem 0;
    }
    .prose hr {
      border: 0;
      border-top: 1px solid var(--rule);
      margin: 2.5rem 0;
    }

    /* Post footer */
    .post-footer {
      margin-top: 3.5rem;
      padding-top: 1.5rem;
      border-top: 1px solid var(--rule);
    }
    .back-link {
      color: var(--accent);
      font-weight: 500;
      font-size: 0.95rem;
    }

    /* Buttons */
    .btn {
      display: inline-block;
      padding: 0.6rem 1.1rem;
      background: var(--accent);
      color: white !important;
      border-radius: 8px;
      font-weight: 500;
      font-size: 0.95rem;
      transition: background 0.15s ease, transform 0.1s ease;
    }
    .btn:hover { background: var(--accent-hover); transform: translateY(-1px); }

    /* Empty / not-found */
    .empty-state, .not-found {
      background: var(--card);
      border: 1px solid var(--rule);
      border-radius: 12px;
      padding: 3rem 2rem;
      text-align: center;
    }
    .not-found h1 { margin: 0.25rem 0 0.75rem; }

    /* Footer */
    .site-footer {
      margin-top: 5rem;
      padding: 2.5rem 0;
      border-top: 1px solid var(--rule);
      background: var(--card);
    }
    .site-footer p { margin: 0.15rem 0; font-size: 0.88rem; }
    .site-footer .brand-mark { margin-right: 0.35rem; }

    .blog-intro { margin: 0 0 2.5rem; max-width: 65ch; }

    /* Tablets */
    @media (max-width: 800px) {
      .container { padding: 0 1.25rem; }
      .post-grid { grid-template-columns: repeat(auto-fill, minmax(240px, 1fr)); }
    }

    /* Phones */
    @media (max-width: 640px) {
      .container { padding: 0 1rem; }
      .nav {
        flex-wrap: wrap;
        gap: 0.75rem;
        padding-top: 0.85rem;
        padding-bottom: 0.85rem;
      }
      .primary-nav {
        gap: 0.9rem;
        flex-wrap: wrap;
      }
      .primary-nav a { font-size: 0.9rem; }
      .content { padding-top: 2rem; padding-bottom: 3rem; }
      .hero { margin-bottom: 2.25rem; }
      .lede { font-size: 1.05rem; }
      .featured-card { padding: 1.3rem; margin-bottom: 2rem; }
      .featured-card h2 { font-size: 1.3rem; }
      .post-grid { grid-template-columns: 1fr; gap: 0.8rem; }
      .post-card { padding: 1.1rem; }
      .post-header, .page-header { margin-bottom: 1.75rem; }
      .prose { font-size: 1rem; line-height: 1.7; }
      .prose pre { padding: 0.85rem 1rem; font-size: 0.85rem; border-radius: 8px; }
      .post-footer { margin-top: 2.5rem; }
      .site-footer { margin-top: 3rem; padding: 2rem 0; }
      .blog-intro { margin-bottom: 2rem; }
    }

    /* Small phones */
    @media (max-width: 380px) {
      .container { padding: 0 0.85rem; }
      .brand-name { font-size: 0.95rem; }
      .featured-card h2 { font-size: 1.2rem; }
    }
    """
  end
end
