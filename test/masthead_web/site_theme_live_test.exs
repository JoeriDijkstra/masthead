defmodule MastheadWeb.SiteThemeLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes, Uploads}

  setup do
    Masthead.Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "st-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "st#{System.unique_integer([:positive])}",
        "name" => "ST Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  test "the selected theme can be changed and saved", %{conn: conn, site: site} do
    tailwind = Themes.get_built_in_by_slug("tailwind")
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/theme")

    lv
    |> form("#site-theme-form", site: %{theme_id: tailwind.id})
    |> render_submit()

    assert Sites.get_site!(site.id).theme_id == tailwind.id
  end

  test "a theme without token categories renders the tokens flat", %{conn: conn, site: site} do
    # Studio's tokens have no category → no accordion (the default theme now
    # groups its tokens, so it would render grouped).
    studio = Themes.get_built_in_by_slug("studio")
    {:ok, site} = Sites.update_settings(site, %{"theme_id" => studio.id})

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/theme")
    refute html =~ "token-group"
  end

  test "a boolean token renders as a checkbox", %{conn: conn, site: site} do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/theme")
    assert html =~ ~s(name="site[theme_tokens][show_search]")
    assert html =~ ~s(type="checkbox")
  end

  test "a boolean token can be toggled on and saved", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/theme")

    lv
    |> form("#site-theme-form", site: %{theme_tokens: %{show_search: "true"}})
    |> render_submit()

    assert Sites.get_site!(site.id).theme_tokens["show_search"] == "true"
  end

  test "a theme with token categories renders accordions, uncategorized under General", %{
    conn: conn,
    site: site
  } do
    tailwind = Themes.get_built_in_by_slug("tailwind")
    {:ok, site} = Sites.update_settings(site, %{"theme_id" => tailwind.id})

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/theme")

    assert html =~ "token-group-summary"
    assert html =~ ~s(phx-value-group="Header")
    assert html =~ ~s(phx-value-group="Footer")
    # logo/favicon/accent/cta have no category → grouped under General.
    assert html =~ ~s(phx-value-group="General")
  end

  test "an opened category stays open across a form change, and only one opens at a time", %{
    conn: conn,
    site: site
  } do
    tailwind = Themes.get_built_in_by_slug("tailwind")
    {:ok, site} = Sites.update_settings(site, %{"theme_id" => tailwind.id})
    {:ok, lv, _} = live(conn, ~p"/#{site.slug}/theme")

    open_header = ~r/<details[^>]*\bopen\b[^>]*>\s*<summary[^>]*phx-value-group="Header"/

    # Open the Header group.
    html = lv |> element(~s(summary[phx-value-group="Header"])) |> render_click()
    assert html =~ open_header

    # A form change (what previously closed it) keeps it open.
    html =
      lv |> form("#site-theme-form", site: %{theme_css_overrides: "/* x */"}) |> render_change()

    assert html =~ open_header

    # Opening Footer closes Header (single-open accordion).
    html = lv |> element(~s(summary[phx-value-group="Footer"])) |> render_click()
    refute html =~ open_header
    assert html =~ ~r/<details[^>]*\bopen\b[^>]*>\s*<summary[^>]*phx-value-group="Footer"/
  end

  test "a file token renders a picker that lists the site's uploads in a modal", %{
    conn: conn,
    site: site
  } do
    upload = create_upload(site, "brand.png")

    {:ok, lv, html} = live(conn, ~p"/#{site.slug}/theme")

    # The field carries a hidden value input and a "Choose file" trigger —
    # no inline <select>. The picker (and its options) is closed initially.
    assert html =~ ~s(name="site[theme_tokens][favicon]")
    assert html =~ "Choose file"
    refute html =~ "Upload new"

    # Opening the picker reveals the upload as a card, a "No file" option, and
    # an "Upload new" add-card.
    html =
      lv
      |> element(~s(button[phx-click="open"][phx-value-token="favicon"]))
      |> render_click()

    assert html =~ "No file"
    assert html =~ "brand.png"
    assert html =~ ~s(phx-value-id="#{upload.id}")
    assert html =~ "Upload new"
  end

  test "selecting an upload and saving persists its id as the token value", %{
    conn: conn,
    site: site
  } do
    upload = create_upload(site, "icon.png")

    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/theme")

    lv
    |> element(~s(button[phx-click="open"][phx-value-token="favicon"]))
    |> render_click()

    # Clicking a card selects it (the picker reports back to the LiveView,
    # which sets the token); the field now shows the chosen filename.
    lv
    |> element(~s(button[phx-click="select"][phx-value-id="#{upload.id}"]))
    |> render_click()

    assert render(lv) =~ "icon.png"

    # Selection is part of the theme form; Save persists it.
    lv |> form("#site-theme-form") |> render_submit()

    site = Sites.get_site!(site.id)
    assert site.theme_tokens["favicon"] == to_string(upload.id)
  end

  test "uploading a new file in the picker stores it and selects it", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/theme")

    lv
    |> element(~s(button[phx-click="open"][phx-value-token="favicon"]))
    |> render_click()

    # The uploader lives behind the "Upload new" add-card.
    lv |> element(~s(button[phx-click="show_upload"])) |> render_click()

    file =
      file_input(lv, "#theme-file-picker-upload-form", :file, [
        %{name: "fresh.png", content: "imgbytes", type: "image/png"}
      ])

    render_upload(file, "fresh.png")
    lv |> element("#theme-file-picker-upload-form") |> render_submit()

    # Stored and immediately selected for the active token.
    assert render(lv) =~ "fresh.png"
    fresh = Enum.find(Uploads.list_uploads(site.id), &(&1.filename == "fresh.png"))
    assert fresh

    lv |> form("#site-theme-form") |> render_submit()
    site = Sites.get_site!(site.id)
    assert site.theme_tokens["favicon"] == to_string(fresh.id)
  end

  test "token inputs are pre-filled with the manifest default when unset", %{
    conn: conn,
    site: site
  } do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/theme")

    # The default theme's accent token defaults to #0066cc — the (color)
    # input must carry that as its value, not render blank/black.
    assert html =~ ~s(value="#0066cc")
  end

  test "a saved override is shown instead of the default", %{conn: conn, site: site} do
    {:ok, site} = Sites.update_settings(site, %{"theme_tokens" => %{"accent" => "#ff0000"}})

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/theme")

    assert html =~ ~s(value="#ff0000")
    refute html =~ ~s(value="#0066cc")
  end

  defp create_upload(site, filename) do
    tmp = Path.join(System.tmp_dir!(), "st-up-#{System.unique_integer([:positive])}.png")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: "image/png", path: tmp})

    File.rm(tmp)
    upload
  end
end
