defmodule MastheadWeb.ThemeLibraryLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "lib-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    theme = upload(user, "My Theme")

    %{user: user, theme: theme, conn: conn_for(user)}
  end

  defp conn_for(user) do
    build_conn()
    |> Plug.Test.init_test_session(%{})
    |> Plug.Conn.put_session(:user_id, user.id)
  end

  defp upload(user, name) do
    {:ok, theme} =
      Themes.create_upload(%{
        slug: "ut#{System.unique_integer([:positive])}",
        name: name,
        version: "1.0.0",
        storage_path: "themes/uploaded/1.0.0",
        owner_id: user.id
      })

    theme
  end

  defp image_file(filename) do
    tmp = Path.join(System.tmp_dir!(), "lib-#{System.unique_integer([:positive])}-#{filename}")
    File.write!(tmp, "bytes")
    %{filename: filename, path: tmp}
  end

  test "owner publishes a custom theme from the modal", %{conn: conn, theme: theme} do
    {:ok, lv, _html} = live(conn, ~p"/themes")

    lv
    |> element(~s(button[phx-click="open_publish"][phx-value-id="#{theme.id}"]))
    |> render_click()

    html = lv |> element("button", "Publish to marketplace") |> render_click()

    assert html =~ "Unpublish"
    assert Themes.get_theme!(theme.id).public
  end

  test "reordering the gallery persists the new order", %{conn: conn, theme: theme} do
    {:ok, a} = Themes.add_theme_image(theme, image_file("a.png"))
    {:ok, b} = Themes.add_theme_image(theme, image_file("b.png"))

    {:ok, lv, _html} = live(conn, ~p"/themes")

    lv
    |> element(~s(button[phx-click="open_publish"][phx-value-id="#{theme.id}"]))
    |> render_click()

    lv
    |> element("#preview-sortable")
    |> render_hook("reorder_previews", %{"ids" => ["#{b.id}", "#{a.id}"]})

    assert Themes.list_theme_images(theme.id) |> Enum.map(& &1.id) == [b.id, a.id]
  end

  test "installed marketplace themes show a green Marketplace chip", %{conn: conn, user: user} do
    {:ok, author} =
      Accounts.register_user(%{
        "email" => "auth-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    other = upload(author, "Shared Theme")
    {:ok, other} = Themes.publish_theme(other)
    {:ok, _} = Themes.install_theme(user.id, other)

    {:ok, _lv, html} = live(conn, ~p"/themes")

    assert html =~ "chip-marketplace"
    assert html =~ "Shared Theme"
  end

  test "uninstalling a marketplace theme removes it from the library", %{conn: conn, user: user} do
    {:ok, author} =
      Accounts.register_user(%{
        "email" => "auth-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    other = upload(author, "Shared Theme")
    {:ok, other} = Themes.publish_theme(other)
    {:ok, _} = Themes.install_theme(user.id, other)

    {:ok, lv, _html} = live(conn, ~p"/themes")
    assert has_element?(lv, "#theme-card-#{other.id}")

    lv
    |> element(~s(button[phx-click="uninstall"][phx-value-id="#{other.id}"]))
    |> render_click()

    refute has_element?(lv, "#theme-card-#{other.id}")
    refute other.id in (Themes.list_themes(user.id) |> Enum.map(& &1.id))
  end
end
