defmodule MastheadWeb.PageFormLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes}

  setup do
    Masthead.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "pf-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "pf#{System.unique_integer([:positive])}",
        "name" => "PF Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  test "a boolean metadata field defaults to its manifest value (checked)", %{
    conn: conn,
    site: site
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages/new")

    # Jump to the Page settings step via the stepper.
    html =
      lv
      |> element(~s(li[phx-click="goto_step"][phx-value-step="3"]))
      |> render_click()

    # The default theme declares show_navigation with "default": true, so a
    # brand-new page must start with the checkbox checked.
    assert html =~ ~s(id="meta-show_navigation")
    assert html =~ ~r/<input[^>]*id="meta-show_navigation"[^>]*checked/
  end
end
