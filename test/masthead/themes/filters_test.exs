defmodule Masthead.Themes.FiltersTest do
  use ExUnit.Case, async: true

  alias Masthead.Themes.Filters

  defp post(title, tags, excerpt \\ "") do
    %{"title" => title, "excerpt" => excerpt, "tags" => tags}
  end

  defp tag(slug), do: %{"name" => slug, "slug" => slug, "color" => nil}

  describe "where_tag/2" do
    setup do
      posts = [
        post("A", [tag("faq"), tag("news")]),
        post("B", [tag("news")]),
        post("C", [])
      ]

      %{posts: posts}
    end

    test "keeps only posts carrying the given tag", %{posts: posts} do
      assert ["A"] == Filters.where_tag(posts, "faq") |> Enum.map(& &1["title"])
      assert ["A", "B"] == Filters.where_tag(posts, "news") |> Enum.map(& &1["title"])
    end

    test "returns an empty list when no post matches", %{posts: posts} do
      assert Filters.where_tag(posts, "nope") == []
    end

    test "tolerates posts with a missing tags key" do
      assert Filters.where_tag([%{"title" => "X"}], "faq") == []
    end

    test "non-list input yields an empty list" do
      assert Filters.where_tag(nil, "faq") == []
      assert Filters.where_tag("not a list", "faq") == []
    end
  end

  describe "search/2" do
    setup do
      posts = [
        post("Elixir tips", [], "pattern matching"),
        post("Phoenix guide", [], "LiveView basics"),
        post("Cooking", [], "ELIXIR of life")
      ]

      %{posts: posts}
    end

    test "matches title or excerpt case-insensitively", %{posts: posts} do
      titles = Filters.search(posts, "elixir") |> Enum.map(& &1["title"])
      assert titles == ["Elixir tips", "Cooking"]
    end

    test "a blank query returns the list unchanged", %{posts: posts} do
      assert Filters.search(posts, "   ") == posts
    end

    test "a non-string query returns the list unchanged", %{posts: posts} do
      assert Filters.search(posts, nil) == posts
    end

    test "non-list input yields an empty list" do
      assert Filters.search(nil, "x") == []
    end
  end
end
