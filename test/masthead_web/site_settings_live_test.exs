defmodule MastheadWeb.SiteSettingsLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes, Uploads}

  setup do
    Masthead.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "ss-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "ss#{System.unique_integer([:positive])}",
        "name" => "SS Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  test "a file token renders as a picker over the site's uploads", %{conn: conn, site: site} do
    upload = create_upload(site, "brand.png")

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")

    # The favicon file token renders a <select>, not a free-text input, and
    # lists the site's existing uploads as options.
    assert html =~ ~s(name="site[theme_tokens][favicon]")
    assert html =~ "— None —"
    assert html =~ ~s(value="#{upload.id}")
    assert html =~ "brand.png"
  end

  test "selecting an upload persists its id as the token value", %{conn: conn, site: site} do
    upload = create_upload(site, "icon.png")

    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/settings")

    lv
    |> form("#site-settings-form", site: %{theme_tokens: %{favicon: to_string(upload.id)}})
    |> render_submit()

    site = Sites.get_site!(site.id)
    assert site.theme_tokens["favicon"] == to_string(upload.id)
  end

  defp create_upload(site, filename) do
    tmp = Path.join(System.tmp_dir!(), "ss-up-#{System.unique_integer([:positive])}.png")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: "image/png", path: tmp})

    File.rm(tmp)
    upload
  end
end
