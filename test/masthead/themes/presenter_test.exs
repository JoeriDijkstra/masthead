defmodule Masthead.Themes.PresenterTest do
  use ExUnit.Case, async: true

  alias Masthead.Content.{Page, Post, Tag}
  alias Masthead.Themes.Presenter

  test "page/1 projects the chosen theme-page template" do
    projected = Presenter.page(%Page{title: "T", slug: "t", format: "theme", template: "blog"})
    assert projected["template"] == "blog"
    assert projected["format"] == "theme"
    assert projected["url"] == "/t"
  end

  test "page/1 leaves template nil for a markdown page" do
    assert Presenter.page(%Page{title: "T", slug: "t", format: "markdown"})["template"] == nil
  end

  test "post/1 projects loaded tags as name/slug maps" do
    post = %Post{
      title: "T",
      slug: "t",
      excerpt: "",
      published_at: nil,
      tags: [%Tag{name: "FAQ", slug: "faq"}]
    }

    assert Presenter.post(post)["tags"] == [%{"name" => "FAQ", "slug" => "faq"}]
  end

  test "post/1 falls back to [] when tags are not loaded" do
    # A freshly-built struct has %Ecto.Association.NotLoaded{} for :tags.
    assert Presenter.post(%Post{title: "T", slug: "t", excerpt: ""})["tags"] == []
  end

  test "tags/2 marks the current slug active" do
    tags = [%Tag{name: "News", slug: "news"}, %Tag{name: "Events", slug: "events"}]

    assert Presenter.tags(tags, "news") == [
             %{"name" => "News", "slug" => "news", "active" => true},
             %{"name" => "Events", "slug" => "events", "active" => false}
           ]
  end

  test "tags/2 with no current slug marks every tag inactive" do
    assert Presenter.tags([%Tag{name: "News", slug: "news"}]) == [
             %{"name" => "News", "slug" => "news", "active" => false}
           ]
  end

  test "tag/1 projects a tag and passes nil through" do
    assert Presenter.tag(%Tag{name: "News", slug: "news"}) == %{
             "name" => "News",
             "slug" => "news"
           }

    assert Presenter.tag(nil) == nil
  end
end
