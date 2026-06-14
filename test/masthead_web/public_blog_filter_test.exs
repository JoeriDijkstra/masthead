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

  defp show(site, slug) do
    conn(:get, "/" <> slug, %{"slug" => slug})
    |> Plug.Conn.assign(:current_site, site)
    |> PublicController.show_page(%{"slug" => slug})
  end

  test "a blog page with a filter tag only lists matching posts", %{site: site, news: news} do
    {:ok, page} =
      Content.create_page(site.id, %{
        "title" => "Updates",
        "slug" => "updates",
        "format" => "blog",
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
        "format" => "blog",
        "published" => "true"
      })

    conn = show(site, page.slug)
    assert conn.resp_body =~ "Tagged update"
    assert conn.resp_body =~ "Unrelated post"
  end
end
