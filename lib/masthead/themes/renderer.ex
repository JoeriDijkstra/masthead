defmodule Masthead.Themes.Renderer do
  @moduledoc """
  Top-level theme render API.

  The public controller calls one of `render_index/1`, `render_post/1`,
  `render_page/1`, `render_blog/1`, `render_not_found/1` with a plain map
  of assigns. The renderer projects the assigns through `Presenter`,
  composes the Liquid context, renders the target template, wraps it in
  the layout, and returns an iodata body ready to send.

  All rendering is sandboxed via `Masthead.Themes.Sandbox` — templates can't
  reach Elixir, the file system, or the database.
  """

  alias Masthead.Themes
  alias Masthead.Themes.{CssSanitizer, Loader, Manifest, Presenter, Sandbox}
  alias Masthead.Uploads

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

  @doc """
  Render a single blog post. The full published-posts list is exposed as
  `posts` too, so a post template can pull related/tagged posts.
  """
  def render_post(%{site: site, post: post, body_html: body_html, pages: pages} = assigns) do
    render(site, :post, %{
      "post" => Presenter.post(post),
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
      "page" => nil,
      "body_html" => body_html
    })
  end

  @doc """
  Render a standalone page (markdown or html). The full published-posts list
  is exposed as `posts` so any page can query posts by tag and render them as
  generic content blocks.
  """
  def render_page(%{site: site, page: page, body_html: body_html, pages: pages} = assigns) do
    render(site, :page, %{
      "page" => Presenter.page(page),
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
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
  def render_not_found(%{site: site, pages: pages} = assigns) do
    render(site, :not_found, %{
      "pages" => Presenter.pages(pages),
      "posts" => Presenter.posts(Map.get(assigns, :posts, [])),
      "post" => nil,
      "page" => nil,
      "body_html" => ""
    })
  end

  @doc """
  Render public search results. Reuses the theme's `index` template (so no
  new required template is introduced) and exposes `search_query` and
  `search_count` so a theme can branch on `{% if search_query %}` to show a
  results heading. `posts` is the already-filtered result set.
  """
  def render_search(%{site: site, posts: posts, query: query, pages: pages}) do
    # Normalise a blank query to nil: an empty string is truthy in Liquid, so
    # leaving it as "" would render a "results for ''" heading on the
    # browse-everything view.
    search_query = if is_binary(query) and String.trim(query) != "", do: query, else: nil

    render(site, :index, %{
      "posts" => Presenter.posts(posts),
      "pages" => Presenter.pages(pages),
      "post" => nil,
      "page" => nil,
      "body_html" => "",
      "search_query" => search_query,
      "search_count" => length(posts)
    })
  end

  # ---- core ----

  defp render(site, target, target_assigns) do
    theme = resolve_theme(site)
    entry = Loader.fetch!(theme)

    file_keys = file_token_keys(entry.manifest)

    tokens =
      entry.manifest
      |> Manifest.effective_tokens(site.theme_tokens || %{})
      |> resolve_file_tokens(file_keys, site)

    base_context = %{
      "site" => Presenter.site(site),
      "theme" => %{
        "name" => entry.theme.name,
        "slug" => entry.theme.slug,
        "version" => entry.theme.version,
        "asset_base" => entry.asset_base,
        "tokens" => tokens,
        "css" => composed_css(entry.css, tokens, file_keys)
      }
    }

    inner_template = Map.fetch!(entry.templates, target)
    layout_template = Map.fetch!(entry.templates, :layout)

    inner_context =
      base_context
      |> Map.merge(target_assigns)
      |> compose_page_metadata(entry.manifest)

    {:ok, inner_iodata, _errs} = Sandbox.render(inner_template, inner_context)
    inner_html = IO.iodata_to_binary(inner_iodata)

    layout_context = Map.put(inner_context, "content", inner_html)
    {:ok, layout_iodata, _errs} = Sandbox.render(layout_template, layout_context)

    IO.iodata_to_binary(layout_iodata)
  end

  # When this render target carries a `page`, replace its raw `metadata`
  # override map with the effective merge against the manifest schema, so
  # templates can read `page.metadata.<key>` and always see a value (the
  # manifest default if the page has no override). Unknown keys on the
  # page survive — theme-switch resilience comes from the manifest layer.
  defp compose_page_metadata(%{"page" => %{} = page} = context, manifest) do
    raw = Map.get(page, "metadata", %{})
    effective = Manifest.effective_metadata(manifest, raw)
    Map.put(context, "page", Map.put(page, "metadata", effective))
  end

  defp compose_page_metadata(context, _manifest), do: context

  defp resolve_theme(%Masthead.Sites.Site{theme_id: id}) when is_integer(id) do
    Themes.get_theme!(id)
  end

  defp resolve_theme(_) do
    # Defensive fallback: a site with no theme_id should never reach
    # production, but if it does we serve the default theme.
    Themes.get_built_in_by_slug("default") ||
      raise "no default theme seeded — run Masthead.Themes.Seed.run/0"
  end

  # The set of token keys declared as `file` in the manifest. These hold an
  # upload id (or "") rather than a literal CSS value, so they're resolved
  # to a URL and emitted as `url(...)` in the cascade.
  defp file_token_keys(%Manifest{tokens: tokens}) do
    for %{key: key, type: "file"} <- tokens, into: MapSet.new(), do: key
  end

  # Replace each `file` token's stored upload id with the upload's public
  # URL. A blank value or a dangling reference (deleted / wrong-site upload)
  # resolves to "" so the template and CSS both fall back to "no file"
  # instead of crashing the public page.
  defp resolve_file_tokens(tokens, file_keys, site) do
    Enum.reduce(file_keys, tokens, fn key, acc ->
      Map.put(acc, key, resolve_upload_url(Map.get(acc, key), site))
    end)
  end

  defp resolve_upload_url(id, site) when is_binary(id) and id != "" do
    case Integer.parse(id) do
      {int_id, ""} ->
        case Uploads.get_upload(site.id, int_id) do
          nil -> ""
          upload -> Uploads.url(upload)
        end

      _ ->
        ""
    end
  end

  defp resolve_upload_url(_id, _site), do: ""

  # Token overrides go AFTER the theme's CSS so they win in the cascade.
  defp composed_css(theme_css, tokens, _file_keys) when map_size(tokens) == 0, do: theme_css

  defp composed_css(theme_css, tokens, file_keys) do
    declarations =
      tokens
      |> Enum.map_join(" ", fn {k, v} -> declaration(k, v, file_keys) end)
      |> String.trim()

    theme_css <> "\n:root { " <> declarations <> " }\n"
  end

  # File tokens carry a resolved URL — wrap it as `url(...)` so themes can
  # write `background: var(--header-image)`. Skip empty file tokens entirely
  # so we never emit a useless `--key: url();`. The URL is sanitized first;
  # we leave it unquoted because the sanitizer strips quotes, and storage
  # keys/slugs never contain spaces or parens.
  defp declaration(key, value, file_keys) do
    if MapSet.member?(file_keys, key) do
      case CssSanitizer.sanitize_token_value(value) do
        "" -> ""
        url -> "--#{kebab(key)}: url(#{url});"
      end
    else
      "--#{kebab(key)}: #{CssSanitizer.sanitize_token_value(value)};"
    end
  end

  defp kebab(key), do: String.replace(key, "_", "-")
end
