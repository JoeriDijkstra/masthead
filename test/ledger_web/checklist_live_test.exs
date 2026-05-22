defmodule LedgerWeb.ChecklistLiveTest do
  use LedgerWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Ledger.{Accounts, Sites}

  setup do
    Ledger.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "cl-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "cl#{System.unique_integer([:positive])}",
        "name" => "CL Test",
        "owner_id" => user.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  test "checklist lists the pending set_description action with its button", %{
    conn: conn,
    site: site
  } do
    {:ok, _lv, html} = live(conn, "/#{site.slug}/checklist")
    assert html =~ "Set the description"
    assert html =~ "Set description"
    assert html =~ ~p"/#{site.slug}/settings"
  end

  test "the overview dashboard surfaces the highest-priority action", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, "/#{site.slug}")
    assert html =~ "action-card"
    # set_description has the highest configured priority
    assert html =~ "Set the description"
  end

  test "dismissing an action removes it and updates the badge count", %{conn: conn, site: site} do
    {:ok, lv, html} = live(conn, "/#{site.slug}/checklist")
    assert html =~ "Set the description"
    # three seeded onboarding actions
    assert html =~ ~s(nav-badge">3)

    html =
      lv
      |> element(~s(button[phx-value-key="set_description"]))
      |> render_click()

    refute html =~ "Set the description"
    assert html =~ ~s(nav-badge">2)
  end

  test "the sidebar shows a red badge with the pending count", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, "/#{site.slug}")
    assert html =~ "nav-badge"
  end

  test "the checklist shows the empty state once every action is done", %{conn: conn, site: site} do
    for key <- ["set_description", "create_first_post", "create_first_page"] do
      :ok = Ledger.Actions.complete_action(site, key)
    end

    {:ok, _lv, html} = live(conn, "/#{site.slug}/checklist")
    assert html =~ "caught up"
    refute html =~ "Set the description"
  end
end
