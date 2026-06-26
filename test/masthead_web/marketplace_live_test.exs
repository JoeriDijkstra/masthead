defmodule MastheadWeb.MarketplaceLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Themes}

  setup do
    Themes.Seed.run()

    user = register("viewer")
    author = register("author")

    %{user: user, author: author, conn: conn_for(user)}
  end

  defp register(prefix) do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    user
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp published(user, name, opts \\ []) do
    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: name,
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    {:ok, theme} = Themes.publish_theme(theme)
    if opts[:verified], do: elem(Themes.verify_theme(theme), 1), else: theme
  end

  test "lists published themes from others with status chips", %{conn: conn, author: author} do
    _verified = published(author, "Verified One", verified: true)
    _community = published(author, "Community One")

    {:ok, _lv, html} = live(conn, ~p"/marketplace")

    assert html =~ "Verified One"
    assert html =~ "Community One"
    # Verified themes get the green chip; community themes show no badge.
    assert html =~ "chip-verified"
    refute html =~ "chip-community"
  end

  test "verified and community filters narrow the list", %{conn: conn, author: author} do
    _verified = published(author, "Verified One", verified: true)
    _community = published(author, "Community One")

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> element(~s(button[phx-value-filter="verified"])) |> render_click()
    assert html =~ "Verified One"
    refute html =~ "Community One"

    html = lv |> element(~s(button[phx-value-filter="community"])) |> render_click()
    assert html =~ "Community One"
    refute html =~ "Verified One"
  end

  test "search narrows themes by name", %{conn: conn, author: author} do
    _sunrise = published(author, "Sunrise")
    _moonset = published(author, "Moonset")

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> form(~s(form[phx-change="search"]), %{query: "sun"}) |> render_change()

    assert html =~ "Sunrise"
    refute html =~ "Moonset"
  end

  test "does not show your own themes", %{conn: conn, user: user} do
    _own = published(user, "My Own Theme")

    {:ok, _lv, html} = live(conn, ~p"/marketplace")
    refute html =~ "My Own Theme"
  end

  test "installing a theme adds it to the library", %{conn: conn, user: user, author: author} do
    theme = published(author, "Installable")

    {:ok, lv, html} = live(conn, ~p"/marketplace")
    assert html =~ "Install"

    html = lv |> element(~s(button[phx-value-id="#{theme.id}"]), "Install") |> render_click()

    assert html =~ "Installed"
    assert theme.id in (Themes.list_themes(user.id) |> Enum.map(& &1.id))
  end

  test "opening the carousel shows images and navigates", %{conn: conn, author: author} do
    theme = published(author, "Gallery Theme")
    {:ok, _} = Themes.add_theme_image(theme, image_file("a.png"))
    {:ok, _} = Themes.add_theme_image(theme, image_file("b.png"))

    {:ok, lv, _html} = live(conn, ~p"/marketplace")

    html = lv |> element(~s(button[phx-click="open_carousel"])) |> render_click()
    assert html =~ "dialog-carousel"
    assert html =~ "1 / 2"

    html = lv |> element(~s(button[phx-value-dir="next"])) |> render_click()
    assert html =~ "2 / 2"

    html = lv |> element(~s(button[phx-click="close_carousel"]), "×") |> render_click()
    refute html =~ "dialog-carousel"
  end

  defp image_file(filename) do
    tmp = Path.join(System.tmp_dir!(), "mk-#{System.unique_integer([:positive])}-#{filename}")
    File.write!(tmp, "bytes")
    %{filename: filename, path: tmp}
  end
end
