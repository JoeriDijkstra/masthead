defmodule Ledger.Themes.RendererTest do
  @moduledoc """
  End-to-end smoke tests for the renderer against the seeded built-in
  themes. We don't assert exact byte-for-byte equality (whitespace differs
  between Liquid and the old HEEx versions) — we check key structural
  elements survive the rewrite.
  """
  use Ledger.DataCase

  alias Ledger.{Accounts, Sites, Content, Themes}
  alias Ledger.Themes.Renderer

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
end
