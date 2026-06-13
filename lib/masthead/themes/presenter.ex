defmodule Masthead.Themes.Presenter do
  @moduledoc """
  Project Ecto schemas into plain maps for use inside Liquid templates.

  This module is the **only** code path through which schema data reaches
  themes. If a field isn't projected here, it isn't reachable from a
  template — that's the trust boundary. Don't widen the projections
  in-place inside the renderer; extend the presenter.

  Keys are strings (Liquid is string-keyed) and the projected shapes are
  deliberately narrow — IDs, foreign keys, internal timestamps, and raw
  unsanitized bodies are not exposed.
  """

  alias Masthead.Sites.Site
  alias Masthead.Content.{Post, Page}
  alias Masthead.Themes.CssSanitizer

  @doc "Project a Site, including the per-site CSS overrides string."
  def site(%Site{} = s) do
    %{
      "name" => s.name,
      "title" => s.title,
      "description" => s.description,
      "slug" => s.slug,
      "css_overrides" => CssSanitizer.sanitize_overrides(s.theme_css_overrides),
      "homepage_slug" => homepage_slug(s)
    }
  end

  # Returns the slug of the page that's currently set as the site's
  # homepage, or `nil` if none is set. Themes use this to know whether
  # the page being rendered is the site's home — useful for applying a
  # special layout or layout class only there.
  defp homepage_slug(%Site{homepage_page_id: nil}), do: nil

  defp homepage_slug(%Site{homepage_page: %Masthead.Content.Page{slug: slug}}), do: slug

  defp homepage_slug(%Site{homepage_page_id: id}) when is_integer(id) do
    # belongs_to wasn't preloaded — one cheap query (id PK lookup).
    case Masthead.Repo.get(Masthead.Content.Page, id) do
      %Masthead.Content.Page{slug: slug} -> slug
      _ -> nil
    end
  end

  defp homepage_slug(_), do: nil

  def post(%Post{} = p) do
    %{
      "title" => p.title,
      "slug" => p.slug,
      "excerpt" => p.excerpt,
      "published_at" => p.published_at,
      "url" => "/posts/" <> p.slug,
      "tags" => tags_of(p)
    }
  end

  # Project a post's tags as plain maps. Defensive against an unloaded
  # association so a caller that forgets to preload gets `[]` rather than a
  # crash on `%Ecto.Association.NotLoaded{}`.
  defp tags_of(%Post{tags: tags}) when is_list(tags) do
    Enum.map(tags, fn t -> %{"name" => t.name, "slug" => t.slug, "color" => t.color} end)
  end

  defp tags_of(_), do: []

  def page(%Page{} = pg) do
    %{
      "title" => pg.title,
      "slug" => pg.slug,
      "format" => pg.format,
      "url" => "/" <> pg.slug,
      # Raw override map. The Renderer merges manifest defaults on top of
      # this before exposing it to templates, so theme authors can read
      # `page.metadata.<key>` and always get the effective value.
      "metadata" => pg.metadata || %{}
    }
  end

  @doc "Convenience: project a list of posts."
  def posts(list) when is_list(list), do: Enum.map(list, &post/1)

  @doc "Convenience: project a list of pages."
  def pages(list) when is_list(list), do: Enum.map(list, &page/1)
end
