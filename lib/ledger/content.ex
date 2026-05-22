defmodule Ledger.Content do
  @moduledoc """
  CRUD for the publishable content of a site: posts and pages.

  Every function is scoped by `site_id`. Callers must pass a site (or its id)
  loaded for the current request/user — there is no global accessor by slug
  alone, on purpose.
  """
  import Ecto.Query
  alias Ledger.Repo
  alias Ledger.Content.{Post, Page}

  # ---- Posts ----

  def list_posts(site_id) do
    Repo.all(from p in Post, where: p.site_id == ^site_id, order_by: [desc: p.inserted_at])
  end

  def list_published_posts(site_id) do
    Repo.all(
      from p in Post,
        where: p.site_id == ^site_id and p.published == true,
        order_by: [desc: p.published_at]
    )
  end

  def get_post!(site_id, id) do
    Repo.one!(from p in Post, where: p.site_id == ^site_id and p.id == ^id)
  end

  def get_published_post_by_slug(site_id, slug) do
    Repo.one(
      from p in Post,
        where: p.site_id == ^site_id and p.slug == ^slug and p.published == true
    )
  end

  def create_post(site_id, attrs) do
    with {:ok, post} <-
           %Post{site_id: site_id}
           |> Post.changeset(Map.put(attrs, "site_id", site_id))
           |> Repo.insert() do
      Ledger.Actions.complete_action(site_id, "create_first_post")
      Ledger.Actions.reached_first_content(site_id)
      {:ok, post}
    end
  end

  def update_post(%Post{} = post, attrs) do
    post |> Post.changeset(attrs) |> Repo.update()
  end

  def delete_post(%Post{} = post), do: Repo.delete(post)

  def change_post(%Post{} = post, attrs \\ %{}), do: Post.changeset(post, attrs)

  # ---- Pages ----

  def list_pages(site_id) do
    Repo.all(from p in Page, where: p.site_id == ^site_id, order_by: p.title)
  end

  def list_published_pages(site_id) do
    Repo.all(
      from p in Page,
        where: p.site_id == ^site_id and p.published == true,
        order_by: p.title
    )
  end

  def get_page!(site_id, id) do
    Repo.one!(from p in Page, where: p.site_id == ^site_id and p.id == ^id)
  end

  def get_published_page_by_slug(site_id, slug) do
    Repo.one(
      from p in Page,
        where: p.site_id == ^site_id and p.slug == ^slug and p.published == true
    )
  end

  @doc """
  Returns the site's designated homepage page, or `nil` if none is set or
  the chosen page isn't currently published. Used by the public root URL
  to decide whether to render a custom page or fall back to the theme's
  default `render_index` (post list).
  """
  def get_homepage_page(%Ledger.Sites.Site{homepage_page_id: nil}), do: nil

  def get_homepage_page(%Ledger.Sites.Site{id: site_id, homepage_page_id: id}) do
    Repo.one(
      from p in Page,
        where: p.id == ^id and p.site_id == ^site_id and p.published == true
    )
  end

  def create_page(site_id, attrs) do
    with {:ok, page} <-
           %Page{site_id: site_id}
           |> Page.changeset(Map.put(attrs, "site_id", site_id))
           |> Repo.insert() do
      Ledger.Actions.complete_action(site_id, "create_first_page")
      Ledger.Actions.reached_first_content(site_id)
      {:ok, page}
    end
  end

  def update_page(%Page{} = page, attrs) do
    page |> Page.changeset(attrs) |> Repo.update()
  end

  def delete_page(%Page{} = page), do: Repo.delete(page)

  def change_page(%Page{} = page, attrs \\ %{}), do: Page.changeset(page, attrs)

  # ---- Rendering ----

  alias Ledger.Content.HTML

  @doc """
  Render a post or page body to safe HTML. Dispatches on `format`:

    * `"markdown"` — parse with Earmark (HTML in source is escaped, so
      `<StrictMode>` inside a fenced code block renders literally), then
      run through the sanitizer as defense in depth.
    * `"html"` — sanitize the raw input directly.

  Returns a string.
  """
  def render_body(nil, _format), do: ""
  def render_body(body, "html") when is_binary(body), do: HTML.sanitize(body)

  def render_body(body, _markdown) when is_binary(body) do
    case Earmark.as_html(body, escape: true, code_class_prefix: "lang-") do
      {:ok, html, _} -> HTML.sanitize(html)
      {:error, html, _} -> HTML.sanitize(html)
    end
  end

  @doc false
  # Kept for backwards compat with anything that still calls it. New
  # callers should pass an explicit format via `render_body/2`.
  def render_markdown(body), do: render_body(body, "markdown")
end
