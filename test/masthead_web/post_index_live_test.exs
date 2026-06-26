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

  describe "tag filtering" do
    setup %{site: site} do
      {:ok, tag} = Content.create_tag(site.id, %{"name" => "News"})

      {:ok, tagged} =
        Content.create_post(site.id, %{"title" => "Tagged story", "tag_ids" => [tag.id]})

      {:ok, untagged} = Content.create_post(site.id, %{"title" => "Lonely note"})
      %{tag: tag, tagged: tagged, untagged: untagged}
    end

    test "filtering by a tag shows only its posts", %{conn: conn, site: site, tag: tag} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/posts?tag=#{tag.slug}")
      assert html =~ "Tagged story"
      refute html =~ "Lonely note"
    end

    test "the Untagged filter hides tagged posts", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/posts?tag=untagged")
      assert html =~ "Lonely note"
      refute html =~ "Tagged story"
    end

    test "searching narrows by title", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

      html =
        lv
        |> form(~s(form.admin-search), %{"scope" => "posts", "query" => "lonely"})
        |> render_change()

      assert html =~ "Lonely note"
      refute html =~ "Tagged story"
    end

    test "clicking a tag pill in a row applies that filter", %{conn: conn, site: site, tag: tag} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts")

      lv
      |> element(~s(button.tag-filter[phx-value-filter="#{tag.slug}"]))
      |> render_click()

      assert_patch(lv, ~p"/#{site.slug}/posts?tag=#{tag.slug}")
      html = render(lv)
      assert html =~ "Tagged story"
      refute html =~ "Lonely note"
    end
  end
end
