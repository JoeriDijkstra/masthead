defmodule Ledger.Themes.Presenter do
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

  alias Ledger.Sites.Site
  alias Ledger.Content.{Post, Page}
  alias Ledger.Themes.CssSanitizer

  @doc "Project a Site, including the per-site CSS overrides string."
  def site(%Site{} = s) do
    %{
      "name" => s.name,
      "title" => s.title,
      "description" => s.description,
      "slug" => s.slug,
      "css_overrides" => CssSanitizer.sanitize_overrides(s.theme_css_overrides)
    }
  end

  def post(%Post{} = p) do
    %{
      "title" => p.title,
      "slug" => p.slug,
      "excerpt" => p.excerpt,
      "published_at" => p.published_at,
      "url" => "/posts/" <> p.slug
    }
  end

  def page(%Page{} = pg) do
    %{
      "title" => pg.title,
      "slug" => pg.slug,
      "format" => pg.format,
      "url" => "/" <> pg.slug
    }
  end

  @doc "Convenience: project a list of posts."
  def posts(list) when is_list(list), do: Enum.map(list, &post/1)

  @doc "Convenience: project a list of pages."
  def pages(list) when is_list(list), do: Enum.map(list, &page/1)
end
