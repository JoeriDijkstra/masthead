defmodule Masthead.Themes.PresenterTest do
  use ExUnit.Case, async: true

  alias Masthead.Content.{Post, Tag}
  alias Masthead.Themes.Presenter

  test "post/1 projects loaded tags as name/slug/color maps" do
    post = %Post{
      title: "T",
      slug: "t",
      excerpt: "",
      published_at: nil,
      tags: [%Tag{name: "FAQ", slug: "faq", color: "#3b82f6"}]
    }

    assert Presenter.post(post)["tags"] == [
             %{"name" => "FAQ", "slug" => "faq", "color" => "#3b82f6"}
           ]
  end

  test "post/1 falls back to [] when tags are not loaded" do
    # A freshly-built struct has %Ecto.Association.NotLoaded{} for :tags.
    assert Presenter.post(%Post{title: "T", slug: "t", excerpt: ""})["tags"] == []
  end
end
