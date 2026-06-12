defmodule Masthead.Content.Import do
  @moduledoc """
  Turns an uploaded file into post/page attributes.

  The format is inferred from the extension (`.html`/`.htm` → HTML, anything
  else → Markdown), the title is humanised from the filename, and the file
  contents become the body. The slug is left blank so the changeset derives
  it from the title.
  """

  @doc """
  Build a `%{"title" => ..., "format" => ..., "slug" => "", "body" => ...}`
  attribute map from an uploaded file's name and contents.
  """
  def attrs_from_file(filename, body) do
    %{
      "format" => format_from_filename(filename),
      "title" => title_from_filename(filename),
      "slug" => "",
      "body" => body
    }
  end

  @doc "Infer the content format from a filename's extension."
  def format_from_filename(name) do
    case name |> Path.extname() |> String.downcase() do
      ext when ext in [".html", ".htm"] -> "html"
      _ -> "markdown"
    end
  end

  @doc """
  Derive a human-friendly title from a filename: drop the extension, turn
  `-`/`_` separators into spaces, and capitalise the first letter.
  """
  def title_from_filename(name) do
    cleaned =
      name
      |> Path.basename()
      |> Path.rootname()
      |> String.replace(["-", "_"], " ")
      |> String.replace(~r/\s+/, " ")
      |> String.trim()

    case cleaned do
      "" -> "Untitled"
      s -> String.upcase(String.first(s)) <> String.slice(s, 1..-1//1)
    end
  end
end
