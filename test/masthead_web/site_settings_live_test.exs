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

  test "a theme without token categories renders the tokens flat", %{conn: conn, site: site} do
    # The default theme's only token (accent) has no category → no accordion.
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")
    refute html =~ "token-group"
  end

  test "a theme with token categories renders accordions, uncategorized under General", %{
    conn: conn,
    site: site
  } do
    tailwind = Themes.get_built_in_by_slug("tailwind")
    {:ok, site} = Sites.update_settings(site, %{"theme_id" => tailwind.id})

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")

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
    {:ok, lv, _} = live(conn, ~p"/#{site.slug}/settings")

    open_header = ~r/<details[^>]*\bopen\b[^>]*>\s*<summary[^>]*phx-value-group="Header"/

    # Open the Header group.
    html = lv |> element(~s(summary[phx-value-group="Header"])) |> render_click()
    assert html =~ open_header

    # A form change (what previously closed it) keeps it open.
    html = lv |> form("#site-settings-form", site: %{name: "Renamed"}) |> render_change()
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

    {:ok, lv, html} = live(conn, ~p"/#{site.slug}/settings")

    # The field carries a hidden value input and a "Choose file" trigger —
    # no inline <select>. The picker (and its options) is closed initially.
    assert html =~ ~s(name="site[theme_tokens][favicon]")
    assert html =~ "Choose file"
    refute html =~ "Upload new"

    # Opening the picker reveals the upload as a card, a "No file" option, and
    # an "Upload new" add-card.
    html =
      lv
      |> element(~s(button[phx-click="open_picker"][phx-value-token="favicon"]))
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

    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/settings")

    lv
    |> element(~s(button[phx-click="open_picker"][phx-value-token="favicon"]))
    |> render_click()

    # Clicking a card selects it (and closes the modal); the field now shows
    # the chosen filename.
    html =
      lv
      |> element(~s(button[phx-click="select_upload"][phx-value-id="#{upload.id}"]))
      |> render_click()

    assert html =~ "icon.png"

    # Selection is part of the settings form; Save persists it.
    lv |> form("#site-settings-form") |> render_submit()

    site = Sites.get_site!(site.id)
    assert site.theme_tokens["favicon"] == to_string(upload.id)
  end

  test "uploading a new file in the picker stores it and selects it", %{conn: conn, site: site} do
    {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/settings")

    lv
    |> element(~s(button[phx-click="open_picker"][phx-value-token="favicon"]))
    |> render_click()

    # The uploader lives behind the "Upload new" add-card.
    lv |> element(~s(button[phx-click="open_uploader"])) |> render_click()

    file =
      file_input(lv, "#token-upload-form", :picker_image, [
        %{name: "fresh.png", content: "imgbytes", type: "image/png"}
      ])

    render_upload(file, "fresh.png")
    html = lv |> element("#token-upload-form") |> render_submit()

    # Stored and immediately selected for the active token.
    assert html =~ "fresh.png"
    fresh = Enum.find(Uploads.list_uploads(site.id), &(&1.filename == "fresh.png"))
    assert fresh

    lv |> form("#site-settings-form") |> render_submit()
    site = Sites.get_site!(site.id)
    assert site.theme_tokens["favicon"] == to_string(fresh.id)
  end

  test "token inputs are pre-filled with the manifest default when unset", %{
    conn: conn,
    site: site
  } do
    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")

    # The default theme's accent token defaults to #0066cc — the (color)
    # input must carry that as its value, not render blank/black.
    assert html =~ ~s(value="#0066cc")
  end

  test "a saved override is shown instead of the default", %{conn: conn, site: site} do
    {:ok, site} = Sites.update_settings(site, %{"theme_tokens" => %{"accent" => "#ff0000"}})

    {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/settings")

    assert html =~ ~s(value="#ff0000")
    refute html =~ ~s(value="#0066cc")
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

  defp create_upload(site, filename) do
    tmp = Path.join(System.tmp_dir!(), "ss-up-#{System.unique_integer([:positive])}.png")
    File.write!(tmp, "bytes")

    {:ok, upload} =
      Uploads.store_image(site, %{filename: filename, content_type: "image/png", path: tmp})

    File.rm(tmp)
    upload
  end
end
