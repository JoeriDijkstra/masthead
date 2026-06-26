defmodule Masthead.Content.LiquidBodyTest do
  @moduledoc """
  The "html" format is Liquid: bodies are rendered through the theme sandbox
  at request time, so the changeset parses them up front and rejects broken
  templates before they can be saved (and 500 a public page).
  """
  use ExUnit.Case, async: true

  alias Masthead.Content.{Page, Post}

  defp page(attrs),
    do: Page.changeset(%Page{}, Map.merge(%{"title" => "T", "site_id" => 1}, attrs))

  defp post(attrs),
    do: Post.changeset(%Post{}, Map.merge(%{"title" => "T", "site_id" => 1}, attrs))

  test "an html page with a valid Liquid body has no body error" do
    cs = page(%{"format" => "html", "body" => "<h1>{{ site.name }}</h1>"})
    refute Keyword.has_key?(cs.errors, :body)
  end

  test "an html page with a broken Liquid body is rejected" do
    cs = page(%{"format" => "html", "body" => "{% if true %}never closed"})
    assert {msg, _} = cs.errors[:body]
    assert msg =~ "Liquid error"
  end

  test "an html body that was HTML-escaped in transit is self-healed, not rejected" do
    escaped = ~s(&lt;p&gt;{% if tag.slug == &quot;emacs&quot; %}yes{% endif %}&lt;/p&gt;)
    cs = page(%{"format" => "html", "body" => escaped})

    refute Keyword.has_key?(cs.errors, :body)

    assert Ecto.Changeset.get_change(cs, :body) ==
             ~s(<p>{% if tag.slug == "emacs" %}yes{% endif %}</p>)
  end

  test "a markdown page is not Liquid-validated" do
    cs = page(%{"format" => "markdown", "body" => "{% if true %}never closed"})
    refute Keyword.has_key?(cs.errors, :body)
  end

  test "an html post with a broken Liquid body is rejected" do
    cs = post(%{"format" => "html", "body" => "{% if true %}never closed"})
    assert {msg, _} = cs.errors[:body]
    assert msg =~ "Liquid error"
  end
end
