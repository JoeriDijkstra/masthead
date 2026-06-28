defmodule Masthead.Content.PageTest do
  use ExUnit.Case, async: true
  alias Masthead.Content.Page

  defp changeset(attrs),
    do: Page.changeset(%Page{}, Map.merge(%{"title" => "T", "site_id" => 1}, attrs))

  test "format must be one of markdown / html / theme" do
    assert changeset(%{"format" => "markdown"}).valid?
    assert changeset(%{"format" => "html"}).valid?
    assert changeset(%{"format" => "theme", "template" => "blog"}).valid?

    refute changeset(%{"format" => "blog"}).valid?
    assert %{format: ["is invalid"]} = errors_on(changeset(%{"format" => "blog"}))
  end

  test "theme pages require a template" do
    cs = changeset(%{"format" => "theme"})
    refute cs.valid?
    assert %{template: ["can't be blank"]} = errors_on(cs)
  end

  test "non-theme pages never carry a template" do
    cs = changeset(%{"format" => "markdown", "template" => "blog"})
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :template) == nil
  end

  test "a theme page keeps its template" do
    cs = changeset(%{"format" => "theme", "template" => "about"})
    assert cs.valid?
    assert Ecto.Changeset.get_field(cs, :template) == "about"
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
