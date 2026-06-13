defmodule MastheadWeb.TagIndexLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Content, Sites, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "ti-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "ti#{System.unique_integer([:positive])}",
        "name" => "TI Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  test "empty state is shown when there are no tags", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/tags")
    assert html =~ "No tags yet"
  end

  test "creating a tag", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/tags/new")

    lv
    |> form("form", tag: %{name: "Announcements", color: "#ff8800"})
    |> render_submit()

    assert_redirect(lv, ~p"/#{site.slug}/tags")

    [tag] = Content.list_tags(site.id)
    assert tag.name == "Announcements"
    assert tag.slug == "announcements"
    assert tag.color == "#ff8800"
  end

  test "validation errors are shown for a blank name", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/tags/new")

    html =
      lv
      |> form("form", tag: %{name: ""})
      |> render_submit()

    assert html =~ "can&#39;t be blank"
    assert Content.list_tags(site.id) == []
  end

  test "editing a tag", %{conn: conn, site: site} do
    {:ok, tag} = Content.create_tag(site.id, %{"name" => "Old"})

    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/tags/#{tag.id}/edit")

    lv
    |> form("form", tag: %{name: "New name", slug: "new-name"})
    |> render_submit()

    assert_redirect(lv, ~p"/#{site.slug}/tags")
    assert Content.get_tag!(site.id, tag.id).slug == "new-name"
  end

  test "deleting a tag", %{conn: conn, site: site} do
    {:ok, tag} = Content.create_tag(site.id, %{"name" => "Temp"})

    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/tags")

    lv
    |> element(~s(button[phx-value-id="#{tag.id}"]))
    |> render_click()

    assert Content.list_tags(site.id) == []
  end
end
