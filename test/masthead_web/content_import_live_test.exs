defmodule MastheadWeb.ContentImportLiveTest do
  use MastheadWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Masthead.{Accounts, Sites, Themes}

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "imp-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "imp#{System.unique_integer([:positive])}",
        "name" => "Import Test",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    conn =
      build_conn()
      |> Plug.Test.init_test_session(%{})
      |> Plug.Conn.put_session(:user_id, user.id)

    %{conn: conn, site: site}
  end

  # Imports a single file end-to-end through the LiveView upload machinery.
  # (LiveViewTest only keeps one simulated upload channel active per input, so
  # consuming *multiple* entries can't be driven here — the bulk path is
  # covered directly in Masthead.ContentImportTest.)
  defp upload_one(lv, entry) do
    file = file_input(lv, "#import-form", :document, [entry])
    render_upload(file, entry.name)
    lv |> form("#import-form") |> render_submit()
  end

  describe "posts" do
    test "the index exposes an Import action", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/posts")
      assert html =~ ~p"/#{site.slug}/posts/import"
    end

    test "the import screen accepts multiple files", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/posts/import")
      # The file input must allow selecting more than one file.
      assert html =~ ~r/<input[^>]*type="file"[^>]*multiple/
    end

    test "importing a single Markdown file lands on the details step prefilled", %{
      conn: conn,
      site: site
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts/import")

      html =
        upload_one(lv, %{name: "My Great Post.md", content: "# Hello", type: "text/markdown"})

      # Step 2 (Details) is now showing, with the title derived from the file.
      assert html =~ ~s(id="meta-form")
      assert html =~ ~s(value="My Great Post")
      assert html =~ ~s(<input type="hidden" name="post[format]" value="markdown")
    end

    test "an HTML file is detected as the html format", %{conn: conn, site: site} do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/posts/import")

      html = upload_one(lv, %{name: "about-us.html", content: "<h1>Hi</h1>", type: "text/html"})

      assert html =~ ~s(value="About us")
      assert html =~ ~s(<input type="hidden" name="post[format]" value="html")
    end
  end

  describe "pages" do
    test "the index exposes an Import action", %{conn: conn, site: site} do
      {:ok, _lv, html} = live(conn, ~p"/#{site.slug}/pages")
      assert html =~ ~p"/#{site.slug}/pages/import"
    end

    test "importing a single file lands on the details step prefilled", %{
      conn: conn,
      site: site
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{site.slug}/pages/import")

      html = upload_one(lv, %{name: "Contact.md", content: "reach us", type: "text/markdown"})

      assert html =~ ~s(id="meta-form")
      assert html =~ ~s(value="Contact")
      assert html =~ ~s(<input type="hidden" name="page[format]" value="markdown")
    end
  end
end
