defmodule MastheadWeb.PostIndexLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Content, Sites, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "pi-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "pi#{System.unique_integer([:positive])}",
        "name" => "PI Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    {:ok, post} =
      Content.create_post(site.id, %{
        "title" => "Hello World",
        "slug" => "hello-world",
        "format" => "markdown",
        "body" => "Hi"
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site, post: post}
  end

  test "clicking a post row navigates to its edit page", %{conn: conn, site: site, post: post} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

    lv
    |> element(~s(tr.row-link))
    |> render_click()

    assert_redirect(lv, ~p"/#{site.slug}/posts/#{post.id}/edit")
  end

  test "the Edit button navigates to the edit page", %{conn: conn, site: site, post: post} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

    lv
    |> element(~s(.row-actions button), "Edit")
    |> render_click()

    assert_redirect(lv, ~p"/#{site.slug}/posts/#{post.id}/edit")
  end

  test "deleting from the row removes the post without navigating", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

    html =
      lv
      |> element(~s(.row-actions button), "Delete")
      |> render_click()

    refute html =~ "Hello World"
    assert Content.list_posts(site.id) == []
  end
end
