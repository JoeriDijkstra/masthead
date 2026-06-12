defmodule Masthead.Content.FrontmatterTest do
  use ExUnit.Case, async: true

  alias Masthead.Content.Frontmatter

  test "parses YAML frontmatter and returns the remaining body" do
    {meta, body} = Frontmatter.split("---\ntitle: Hello\ndraft: false\n---\nThe body")

    assert meta == %{"title" => "Hello", "draft" => "false"}
    assert body == "The body"
  end

  test "parses TOML frontmatter (+++) with `=` and quoted values" do
    {meta, body} = Frontmatter.split(~s(+++\ntitle = "Hello"\ndraft = true\n+++\nBody))

    assert meta["title"] == "Hello"
    assert meta["draft"] == "true"
    assert body == "Body"
  end

  test "returns empty meta and untouched body when there is no frontmatter" do
    assert Frontmatter.split("Just text") == {%{}, "Just text"}
  end

  test "a `---` later in the body is not treated as frontmatter" do
    body = "Intro\n\n---\n\nMore"
    assert Frontmatter.split(body) == {%{}, body}
  end

  test "tolerates CRLF line endings" do
    {meta, body} = Frontmatter.split("---\r\ntitle: Hi\r\n---\r\nBody")
    assert meta["title"] == "Hi"
    assert body == "Body"
  end
end
