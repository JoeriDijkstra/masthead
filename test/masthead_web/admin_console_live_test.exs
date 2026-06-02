defmodule MastheadWeb.AdminConsoleLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites}

  setup do
    Masthead.Themes.Seed.run()

    {:ok, admin} =
      Accounts.register_user(%{
        "email" => "admin-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, admin} = Accounts.set_admin(admin, true)

    {:ok, member} =
      Accounts.register_user(%{
        "email" => "member-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "mem#{System.unique_integer([:positive])}",
        "name" => "Member Site",
        "owner_id" => member.id
      })

    %{admin: admin, member: member, site: site, conn: conn_for(admin)}
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  test "non-admins are redirected away from /admin", %{member: member} do
    assert {:error, {:redirect, %{to: "/"}}} = live(conn_for(member), ~p"/admin")
  end

  test "admin sees all users, sites and themes", %{conn: conn, member: member, site: site} do
    {:ok, lv, html} = live(conn, ~p"/admin")

    # Users tab (default).
    assert html =~ member.email

    # Sites tab.
    html = lv |> element(~s(button[phx-value-tab="sites"])) |> render_click()
    assert html =~ site.name
    assert html =~ member.email

    # Themes tab.
    html = lv |> element(~s(button[phx-value-tab="themes"])) |> render_click()
    assert html =~ "Tailwind"
  end

  test "admin can verify an unverified user", %{conn: conn, member: member} do
    refute Accounts.User.confirmed?(member)
    {:ok, lv, _} = live(conn, ~p"/admin")

    lv
    |> element(~s(button[phx-click="verify_user"][phx-value-id="#{member.id}"]))
    |> render_click()

    assert Accounts.get_user!(member.id) |> Accounts.User.confirmed?()
  end

  test "admin can disable and re-enable a site", %{conn: conn, site: site} do
    {:ok, lv, _} = live(conn, ~p"/admin")
    lv |> element(~s(button[phx-value-tab="sites"])) |> render_click()

    lv
    |> element(~s(button[phx-click="disable_site"][phx-value-id="#{site.id}"]))
    |> render_click()

    assert Sites.get_site!(site.id).disabled_at

    lv
    |> element(~s(button[phx-click="enable_site"][phx-value-id="#{site.id}"]))
    |> render_click()

    refute Sites.get_site!(site.id).disabled_at
  end

  test "admin can soft-delete and restore a site", %{conn: conn, site: site} do
    {:ok, lv, _} = live(conn, ~p"/admin")
    lv |> element(~s(button[phx-value-tab="sites"])) |> render_click()

    lv
    |> element(~s(button[phx-click="delete_site"][phx-value-id="#{site.id}"]))
    |> render_click()

    assert Sites.get_site!(site.id).deleted_at

    lv
    |> element(~s(button[phx-click="restore_site"][phx-value-id="#{site.id}"]))
    |> render_click()

    refute Sites.get_site!(site.id).deleted_at
  end

  test "admin can add a custom action to a site via the modal", %{conn: conn, site: site} do
    {:ok, lv, _} = live(conn, ~p"/admin")
    lv |> element(~s(button[phx-value-tab="sites"])) |> render_click()

    lv
    |> element(~s(button[phx-click="open_action_modal"][phx-value-site_id="#{site.id}"]))
    |> render_click()

    lv
    |> form(~s(form[phx-submit="create_action"]), %{
      title: "Please add a logo",
      message: "Your header looks bare."
    })
    |> render_submit()

    action = Enum.find(Masthead.Actions.list_pending(site), &(&1.title == "Please add a logo"))
    assert action
    assert action.message == "Your header looks bare."
  end

  test "admin can enter another person's site at owner level", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}")
    # The site dashboard loads (admin bypassed the ownership check).
    assert html =~ site.name
  end

  test "admin can download an uploaded theme as a zip", %{conn: conn, member: member} do
    slug = "dl#{System.unique_integer([:positive])}"
    {:ok, theme} = install_uploaded_theme(slug, member.id)

    conn = get(conn, ~p"/admin/themes/#{theme.id}/download")

    assert response_content_type(conn, :zip) =~ "zip"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ "#{slug}-1.0.0.zip"
    # The body is a real zip (PK magic bytes).
    assert binary_part(conn.resp_body, 0, 2) == "PK"
  end

  defp install_uploaded_theme(slug, owner_id) do
    files = %{
      "manifest.json" =>
        Jason.encode!(%{
          "name" => "DL #{slug}",
          "slug" => slug,
          "version" => "1.0.0",
          "tokens" => []
        }),
      "templates/layout.liquid" => "<html><body>{{ content }}</body></html>",
      "templates/index.liquid" => "<h1>{{ site.name }}</h1>",
      "templates/post.liquid" => "<article>{{ body_html }}</article>",
      "templates/page.liquid" => "<article>{{ body_html }}</article>",
      "templates/blog.liquid" => "<h1>{{ page.title }}</h1>",
      "templates/not_found.liquid" => "<h1>Not found</h1>",
      "theme.css" => "body{}"
    }

    tmp = Path.join(System.tmp_dir!(), "dl-#{System.unique_integer([:positive])}.zip")
    entries = Enum.map(files, fn {n, b} -> {String.to_charlist(n), b} end)
    {:ok, _} = :zip.create(String.to_charlist(tmp), entries)
    result = Masthead.Themes.Package.install(tmp, owner_id)
    File.rm(tmp)
    result
  end
end
