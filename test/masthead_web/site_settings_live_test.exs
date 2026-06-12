defmodule MastheadWeb.SiteSettingsLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes}

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

  test "the settings page no longer carries the theme controls", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")

    # Theme selection/customization now lives on its own /theme page.
    refute html =~ "theme-picker"
    refute html =~ ~s(name="site[theme_id]")
    assert html =~ "Identity"
    assert html =~ "Custom domain"
  end

  test "identity fields can be edited and saved", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/settings")

    lv
    |> form("#site-settings-form", site: %{name: "Renamed", description: "A fresh tagline."})
    |> render_submit()

    site = Sites.get_site!(site.id)
    assert site.name == "Renamed"
    assert site.description == "A fresh tagline."
  end

  test "the owner can soft-delete their site from the danger zone", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/settings")

    lv |> element("button", "Delete site") |> render_click()

    assert_redirect(lv, ~p"/sites")

    # The row is retained (soft delete) but hidden from the owner's list and
    # no longer resolvable as their site.
    assert Sites.get_site!(site.id).deleted_at != nil
    assert Sites.list_sites_for_user(site.owner_id) == []
  end

  test "a Hugo site can be imported from the Import block", %{conn: conn, site: site} do
    {:ok, lv, html} = live(conn, ~p"/#{site.slug}/settings")
    assert html =~ "Import site"

    zip =
      hugo_zip(%{
        "content/posts/hello.md" => "---\ntitle: Hello\ndraft: false\n---\nHi there.",
        "content/about.md" => "---\ntitle: About\n---\nAbout us.",
        "config.toml" => "x = 1"
      })

    file =
      file_input(lv, "#site-import-form", :site_archive, [
        %{name: "site.zip", content: zip, type: "application/zip"}
      ])

    render_upload(file, "site.zip")
    html = lv |> element("#site-import-form") |> render_submit()

    assert html =~ "Imported 1 posts, 1 pages"
    assert length(Masthead.Content.list_posts(site.id)) == 1
    assert length(Masthead.Content.list_pages(site.id)) == 1
  end

  # Builds an in-memory zip of a Hugo source tree from a relpath => content map.
  defp hugo_zip(files) do
    base = Path.join(System.tmp_dir!(), "ss-hugo-#{System.unique_integer([:positive])}")

    for {rel, content} <- files do
      abs = Path.join(base, rel)
      File.mkdir_p!(Path.dirname(abs))
      File.write!(abs, content)
    end

    rels = files |> Map.keys() |> Enum.map(&String.to_charlist/1)

    {:ok, {_name, bytes}} =
      :zip.create(~c"site.zip", rels, [:memory, cwd: String.to_charlist(base)])

    File.rm_rf(base)
    bytes
  end
end
