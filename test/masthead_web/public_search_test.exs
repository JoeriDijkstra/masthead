defmodule MastheadWeb.PublicSearchTest do
  use Masthead.DataCase

  import Plug.Test, only: [conn: 3]

  alias Masthead.{Accounts, Content, Sites, Themes}
  alias MastheadWeb.PublicController

  setup do
    Themes.Seed.run()

    {:ok, user} =
      Accounts.register_user(%{
        "email" => "search-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    default = Themes.get_built_in_by_slug("default")

    {:ok, site} =
      Sites.create_site(%{
        "slug" => "search#{System.unique_integer([:positive])}",
        "name" => "Search Site",
        "owner_id" => user.id,
        "theme_id" => default.id
      })

    {:ok, _published} =
      Content.create_post(site.id, %{
        "title" => "Elixir patterns",
        "body" => "GenServers and supervisors",
        "published" => true
      })

    {:ok, _draft} =
      Content.create_post(site.id, %{
        "title" => "Secret elixir draft",
        "body" => "not ready",
        "published" => false
      })

    %{site: site}
  end

  defp search(site, q) do
    conn(:get, "/search", %{"q" => q})
    |> Plug.Conn.assign(:current_site, site)
    |> PublicController.search(%{"q" => q})
  end

  test "matches published posts and excludes drafts", %{site: site} do
    conn = search(site, "elixir")
    assert conn.status == 200
    assert conn.resp_body =~ "Elixir patterns"
    refute conn.resp_body =~ "Secret elixir draft"
  end

  test "shows the result summary for the query", %{site: site} do
    conn = search(site, "elixir")
    assert conn.resp_body =~ "1 result"
    assert conn.resp_body =~ "elixir"
  end

  test "an empty query lists all published posts", %{site: site} do
    conn = search(site, "")
    assert conn.status == 200
    assert conn.resp_body =~ "Elixir patterns"
    refute conn.resp_body =~ "No posts match your search."
    refute conn.resp_body =~ "Secret elixir draft"
  end
end
