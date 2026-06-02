defmodule Masthead.Themes.RendererTest do
  @moduledoc """
  End-to-end smoke tests for the renderer against the seeded built-in
  themes. We don't assert exact byte-for-byte equality (whitespace differs
  between Liquid and the old HEEx versions) — we check key structural
  elements survive the rewrite.
  """
  use Masthead.DataCase

  alias Masthead.{Accounts, Sites, Content, Themes}
  alias Masthead.Themes.Renderer

  setup do
    # Built-in themes are seeded at application boot; if a test re-runs in
    # a fresh sandbox we need to make sure the rows exist within the
    # sandbox connection.
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "renderer-test-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "rtest#{System.unique_integer([:positive])}",
        "name" => "Renderer Test",
        "title" => "Renderer Test Site",
        "description" => "Test description.",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    {:ok, _post} =
      Content.create_post(site.id, %{
        "title" => "Hello",
        "excerpt" => "An excerpt.",
        "body" => "Just the body.",
        "published" => true
      })

    {:ok, _page} =
      Content.create_page(site.id, %{
        "title" => "About",
        "body" => "About body.",
        "published" => true
      })

    %{site: Sites.get_site!(site.id), user: user}
  end

  describe "render_index/1" do
    test "lists posts and includes site title", %{site: site} do
      posts = Content.list_published_posts(site.id)
      pages = Content.list_published_pages(site.id)
      out = Renderer.render_index(%{site: site, posts: posts, pages: pages})

      assert out =~ "<!DOCTYPE html>"
      assert out =~ site.title
      assert out =~ "Hello"
      assert out =~ "/posts/hello"
    end

    test "renders empty state when no posts", %{site: site} do
      pages = Content.list_published_pages(site.id)
      out = Renderer.render_index(%{site: site, posts: [], pages: pages})
      assert out =~ "No posts yet"
    end
  end

  describe "render_post/1" do
    test "includes title and body_html", %{site: site} do
      [post | _] = Content.list_published_posts(site.id)
      pages = Content.list_published_pages(site.id)
      body_html = Content.render_body(post.body, post.format)

      out =
        Renderer.render_post(%{site: site, post: post, body_html: body_html, pages: pages})

      assert out =~ "<title>"
      assert out =~ post.title
      assert out =~ body_html
    end
  end

  describe "render_page/1" do
    test "renders the page body via body_html", %{site: site} do
      [page | _] = Content.list_published_pages(site.id)
      pages = Content.list_published_pages(site.id)
      body_html = Content.render_body(page.body, page.format)

      out =
        Renderer.render_page(%{site: site, page: page, body_html: body_html, pages: pages})

      assert out =~ "About body."
    end
  end

  describe "render_not_found/1" do
    test "produces a 404 body", %{site: site} do
      pages = Content.list_published_pages(site.id)
      out = Renderer.render_not_found(%{site: site, pages: pages})
      assert out =~ "Not found"
    end
  end

  describe "escaping" do
    test "site name is HTML-escaped in templates", %{user: user} do
      default = Themes.get_built_in_by_slug("default")

      {:ok, evil} =
        Sites.create_site(%{
          "slug" => "evil#{System.unique_integer([:positive])}",
          "name" => "<script>alert(1)</script>",
          "owner_id" => user.id,
          "theme_id" => default.id
        })

      out = Renderer.render_index(%{site: evil, posts: [], pages: []})
      refute out =~ "<script>alert(1)</script>"
      assert out =~ "&lt;script&gt;"
    end
  end

  describe "tokens" do
    test "default token values appear in the inlined <style>", %{site: site} do
      pages = Content.list_published_pages(site.id)
      out = Renderer.render_index(%{site: site, posts: [], pages: pages})

      # Default theme exposes "accent" with default #0066cc
      assert out =~ "--accent: #0066cc"
    end

    test "per-site token override beats the manifest default", %{site: site} do
      {:ok, site} = Sites.update_settings(site, %{"theme_tokens" => %{"accent" => "#ff0000"}})

      site = Sites.get_site!(site.id)
      pages = Content.list_published_pages(site.id)
      out = Renderer.render_index(%{site: site, posts: [], pages: pages})

      assert out =~ "--accent: #ff0000"
    end
  end

  describe "page metadata" do
    setup %{user: user, site: site} do
      # Install a tiny theme that declares a metadata schema and uses it
      # in page.liquid. Stripped down to just what we need to test.
      slug = "metatest#{System.unique_integer([:positive])}"
      zip_path = build_metadata_theme_zip(slug)

      {:ok, theme} = Masthead.Themes.Package.install(zip_path, user.id)
      File.rm(zip_path)
      {:ok, site} = Sites.update_settings(site, %{"theme_id" => theme.id})
      site = Sites.get_site!(site.id)

      {:ok, theme: theme, site: site}
    end

    test "manifest defaults reach the template", %{site: site} do
      [page | _] = Content.list_published_pages(site.id)
      pages = Content.list_published_pages(site.id)
      body_html = Content.render_body(page.body, page.format)

      out =
        Renderer.render_page(%{
          site: site,
          page: page,
          body_html: body_html,
          pages: pages
        })

      assert out =~ ~s(data-layout="contained")
    end

    test "per-page overrides win over manifest defaults", %{site: site} do
      [page | _] = Content.list_published_pages(site.id)
      {:ok, page} = Content.update_page(page, %{"metadata" => %{"layout" => "wide"}})

      pages = Content.list_published_pages(site.id)
      body_html = Content.render_body(page.body, page.format)

      out =
        Renderer.render_page(%{
          site: site,
          page: page,
          body_html: body_html,
          pages: pages
        })

      assert out =~ ~s(data-layout="wide")
    end

    test "empty-string metadata override falls back to default", %{site: site} do
      [page | _] = Content.list_published_pages(site.id)
      # Empty values are stripped by the Page changeset's normalize_metadata.
      {:ok, page} = Content.update_page(page, %{"metadata" => %{"layout" => ""}})
      assert page.metadata == %{}

      pages = Content.list_published_pages(site.id)
      body_html = Content.render_body(page.body, page.format)

      out =
        Renderer.render_page(%{
          site: site,
          page: page,
          body_html: body_html,
          pages: pages
        })

      assert out =~ ~s(data-layout="contained")
    end

    test "unknown keys (from a previous theme) are preserved on save", %{site: site} do
      [page | _] = Content.list_published_pages(site.id)

      {:ok, page} =
        Content.update_page(page, %{"metadata" => %{"from_old_theme" => "still here"}})

      assert page.metadata["from_old_theme"] == "still here"
    end
  end

  # Helper: write a minimal zipped theme that surfaces page.metadata.layout
  # via a data attribute in the rendered HTML.
  defp build_metadata_theme_zip(slug) do
    files = %{
      "manifest.json" =>
        Jason.encode!(%{
          "name" => "Meta " <> slug,
          "slug" => slug,
          "version" => "1.0.0",
          "tokens" => [],
          "metadata" => [
            %{
              "key" => "layout",
              "label" => "Layout",
              "type" => "select",
              "options" => ["contained", "wide"],
              "default" => "contained"
            }
          ]
        }),
      "templates/layout.liquid" => "<html><head></head><body>{{ content }}</body></html>",
      "templates/index.liquid" => "<h1>{{ site.name | escape }}</h1>",
      "templates/post.liquid" => "<article>{{ body_html }}</article>",
      "templates/page.liquid" =>
        "<article data-layout=\"{{ page.metadata.layout }}\">{{ body_html }}</article>",
      "templates/blog.liquid" => "<h1>{{ page.title | escape }}</h1>",
      "templates/not_found.liquid" => "<h1>Not found</h1>",
      "theme.css" => "body { background: white; }"
    }

    tmp = Path.join(System.tmp_dir!(), "metatest-#{System.unique_integer([:positive])}.zip")
    entries = Enum.map(files, fn {n, b} -> {String.to_charlist(n), b} end)
    {:ok, _} = :zip.create(String.to_charlist(tmp), entries)
    tmp
  end
end
