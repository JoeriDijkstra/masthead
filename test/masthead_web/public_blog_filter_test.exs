defmodule MastheadWeb.PublicBlogFilterTest do
  use Masthead.DataCase

  import Plug.Test, only: [conn: 3]

  alias Masthead.{Accounts, Content, Sites, Themes}
  alias MastheadWeb.PublicController

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "blog-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "blog#{System.unique_integer([:positive])}",
        "name" => "Blog Site",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    {:ok, news} = Content.create_tag(site.id, %{"name" => "News"})

    {:ok, _tagged} =
      Content.create_post(site.id, %{
        "title" => "Tagged update",
        "published" => "true",
        "tag_ids" => [news.id]
      })

    {:ok, _other} =
      Content.create_post(site.id, %{"title" => "Unrelated post", "published" => "true"})

    %{site: site, news: news}
  end

  defp show(site, slug, extra_params \\ %{}) do
    params = Map.merge(%{"slug" => slug}, extra_params)

    conn(:get, "/" <> slug, params)
    |> Plug.Conn.assign(:current_site, site)
    |> PublicController.show_page(%{"slug" => slug})
  end

  test "a blog page with a filter tag only lists matching posts", %{site: site, news: news} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Updates",
        "slug" => "updates",
        "format" => "theme",
        "template" => "blog",
        "published" => "true",
        "filter_tag_ids" => [news.id]
      })

    conn = show(site, page.slug)
    assert conn.status == 200
    assert conn.resp_body =~ "Tagged update"
    refute conn.resp_body =~ "Unrelated post"
  end

  test "a blog page with no filter tags lists every published post", %{site: site} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Everything",
        "slug" => "everything",
        "format" => "theme",
        "template" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug)
    assert conn.resp_body =~ "Tagged update"
    assert conn.resp_body =~ "Unrelated post"
  end

  test "?tag narrows an unfiltered blog page to a single tag", %{site: site, news: news} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Everything",
        "slug" => "everything",
        "format" => "theme",
        "template" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug, %{"tag" => news.slug})
    assert conn.resp_body =~ "Tagged update"
    refute conn.resp_body =~ "Unrelated post"
  end

  test "an unknown ?tag slug is ignored and the page shows its full list", %{site: site} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Everything",
        "slug" => "everything",
        "format" => "theme",
        "template" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug, %{"tag" => "does-not-exist"})
    assert conn.resp_body =~ "Tagged update"
    assert conn.resp_body =~ "Unrelated post"
  end

  test "?tag only resolves within a page's configured filter_tags", %{site: site, news: news} do
    {:ok, events} = Content.create_tag(site.id, %{"name" => "Events"})

    {:ok, _event_post} =
      Content.create_post(site.id, %{
        "title" => "Event post",
        "published" => "true",
        "tag_ids" => [events.id]
      })

    # Page is scoped to News only; a ?tag pointing at Events is out of scope
    # and must fall back to the page's News list, never leaking Event posts.
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Updates",
        "slug" => "updates",
        "format" => "theme",
        "template" => "blog",
        "published" => "true",
        "filter_tag_ids" => [news.id]
      })

    conn = show(site, page.slug, %{"tag" => events.slug})
    assert conn.resp_body =~ "Tagged update"
    refute conn.resp_body =~ "Event post"
  end

  test "the blog template renders a tag-filter bar with a link per tag", %{site: site, news: news} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Everything",
        "slug" => "everything",
        "format" => "theme",
        "template" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug)
    assert conn.resp_body =~ ~s(class="tag-filter")
    assert conn.resp_body =~ ~s(href="?tag=#{news.slug}")
    assert conn.resp_body =~ "News"
  end

  test "the active tag is marked in the filter bar", %{site: site, news: news} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Everything",
        "slug" => "everything",
        "format" => "theme",
        "template" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug, %{"tag" => news.slug})
    assert conn.resp_body =~ "tag-filter-item-active"
  end

  defp index(site, params \\ %{}) do
    conn(:get, "/", params)
    |> Plug.Conn.assign(:current_site, site)
    |> PublicController.index(params)
  end

  test "the index renders a tag filter bar only when show_tags is on", %{site: site, news: news} do
    {:ok, site} = Sites.update_settings(site, %{"theme_tokens" => %{"show_tags" => "true"}})

    conn = index(site)
    assert conn.resp_body =~ ~s(class="tag-filter")
    assert conn.resp_body =~ ~s(href="?tag=#{news.slug}")
  end

  test "the index hides the tag filter bar when show_tags is off", %{site: site} do
    conn = index(site)
    refute conn.resp_body =~ ~s(class="tag-filter")
  end

  test "the index narrows posts by ?tag regardless of the token", %{site: site, news: news} do
    conn = index(site, %{"tag" => news.slug})
    assert conn.resp_body =~ "Tagged update"
    refute conn.resp_body =~ "Unrelated post"
  end
end
