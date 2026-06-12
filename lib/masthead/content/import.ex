defmodule Masthead.Content.Import do
  @moduledoc """
  Turns an uploaded file into post/page attributes.

  The format is inferred from the extension (`.html`/`.htm` → HTML, anything
  else → Markdown) and the file contents become the body.

  If the file opens with a frontmatter block (YAML `---` or TOML `+++`, the
  Hugo/Jekyll defaults — see `Masthead.Content.Frontmatter`) it is stripped
  from the body and used to seed attributes:

      ---
      title: "Compressing images in Elixir with Mogrify"
      date: 2024-02-14T19:57:24+01:00
      draft: false
      ---

  `title` overrides the filename-derived title, and `draft` drives the
  published state (`draft: false` → published, `draft: true`/absent → draft).
  """

  alias Masthead.Content.Frontmatter

  @doc """
  Build a `%{"title" => ..., "format" => ..., "slug" => "", "body" => ...,
  "published" => ...}` attribute map from an uploaded file's name and contents.
  """
  def attrs_from_file(filename, body) do
    {meta, content} = Frontmatter.split(body)

    %{
      "format" => format_from_filename(filename),
      "title" => frontmatter_title(meta) || title_from_filename(filename),
      "slug" => "",
      "body" => content,
      "published" => to_string(published?(meta))
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

  @doc """
  The frontmatter `title`, or `nil` when absent/blank so callers can fall
  back to a filename-derived title.
  """
  def frontmatter_title(meta) do
    case meta["title"] do
      title when is_binary(title) ->
        case String.trim(title) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  @doc """
  Whether imported content should be published. Published only when
  frontmatter explicitly says `draft: false`; no frontmatter, no `draft`
  key, or `draft: true` all mean "keep it a draft".
  """
  def published?(meta) do
    case Map.get(meta, "draft") do
      nil -> false
      value -> not truthy?(value)
    end
  end

  defp truthy?(value) do
    normalized = value |> to_string() |> String.trim() |> String.downcase()
    normalized in ~w(true yes 1)
  end
end
