defmodule Ledger.Themes.Renderer do
  @moduledoc """
  Top-level theme render API.

  The public controller calls one of `render_index/1`, `render_post/1`,
  `render_page/1`, `render_blog/1`, `render_not_found/1` with a plain map
  of assigns. The renderer projects the assigns through `Presenter`,
  composes the Liquid context, renders the target template, wraps it in
  the layout, and returns an iodata body ready to send.

  All rendering is sandboxed via `Ledger.Themes.Sandbox` — templates can't
  reach Elixir, the file system, or the database.
  """

  alias Ledger.Themes
  alias Ledger.Themes.{CssSanitizer, Loader, Manifest, Presenter, Sandbox}

  @doc "Render the site homepage (post list)."
  def render_index(%{site: site, posts: posts, pages: pages}) do
    render(site, :index, %{
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  @doc "Render a single blog post."
  def render_post(%{site: site, post: post, body_html: body_html, pages: pages}) do
    render(site, :post, %{
      "post" => Presenter.post(post),
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "page" => nil,
      "body_html" => body_html
    })
  end

  @doc "Render a standalone page (markdown or html)."
  def render_page(%{site: site, page: page, body_html: body_html, pages: pages}) do
    render(site, :page, %{
      "page" => Presenter.page(page),
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "post" => nil,
      "body_html" => body_html
    })
  end

  @doc "Render a blog-format page: intro + post list."
  def render_blog(%{site: site, page: page, posts: posts, body_html: body_html, pages: pages}) do
    render(site, :blog, %{
      "page" => Presenter.page(page),
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "post" => nil,
      "body_html" => body_html
    })
  end

  @doc "Render the site-scoped 404."
  def render_not_found(%{site: site, pages: pages}) do
    render(site, :not_found, %{
      "pages" => Presenter.pages(pages),
      "posts" => [],
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  # ---- core ----

  defp render(site, target, target_assigns) do
    theme = resolve_theme(site)
    entry = Loader.fetch!(theme)
    tokens = Manifest.effective_tokens(entry.manifest, site.theme_tokens || %{})

    base_context = %{
      "site" => Presenter.site(site),
      "theme" => %{
        "name" => entry.theme.name,
        "slug" => entry.theme.slug,
        "version" => entry.theme.version,
        "asset_base" => entry.asset_base,
        "tokens" => tokens,
        "css" => composed_css(entry.css, tokens)
      }
    }

    inner_template = Map.fetch!(entry.templates, target)
    layout_template = Map.fetch!(entry.templates, :layout)

    inner_context = Map.merge(base_context, target_assigns)
    {:ok, inner_iodata, _errs} = Sandbox.render(inner_template, inner_context)
    inner_html = IO.iodata_to_binary(inner_iodata)

    layout_context = Map.put(inner_context, "content", inner_html)
    {:ok, layout_iodata, _errs} = Sandbox.render(layout_template, layout_context)

    IO.iodata_to_binary(layout_iodata)
  end

  defp resolve_theme(%Ledger.Sites.Site{theme_id: id}) when is_integer(id) do
    Themes.get_theme!(id)
  end

  defp resolve_theme(_) do
    # Defensive fallback: a site with no theme_id should never reach
    # production, but if it does we serve the default theme.
    Themes.get_built_in_by_slug("default") ||
      raise "no default theme seeded — run Ledger.Themes.Seed.run/0"
  end

  # Token overrides go AFTER the theme's CSS so they win in the cascade.
  defp composed_css(theme_css, tokens) when map_size(tokens) == 0, do: theme_css

  defp composed_css(theme_css, tokens) do
    declarations =
      tokens
      |> Enum.map_join(" ", fn {k, v} ->
        "--#{kebab(k)}: #{CssSanitizer.sanitize_token_value(v)};"
      end)

    theme_css <> "\n:root { " <> declarations <> " }\n"
  end

  defp kebab(key), do: String.replace(key, "_", "-")
end
