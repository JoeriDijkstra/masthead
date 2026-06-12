defmodule Masthead.Content.Import do
  @moduledoc """
  Turns an uploaded file into post/page attributes.

  The format is inferred from the extension (`.html`/`.htm` → HTML, anything
  else → Markdown) and the file contents become the body.

  If the file opens with a YAML frontmatter block (Hugo/Jekyll style), it is
  stripped from the body and used to seed attributes:

      ---
      title: "Compressing images in Elixir with Mogrify"
      date: 2024-02-14T19:57:24+01:00
      draft: false
      ---

  `title` overrides the filename-derived title, and `draft` drives the
  published state (`draft: false` → published, `draft: true`/absent → draft).
  We only read the handful of keys we care about rather than pull in a full
  YAML dependency.
  """

  @doc """
  Build a `%{"title" => ..., "format" => ..., "slug" => "", "body" => ...,
  "published" => ...}` attribute map from an uploaded file's name and contents.
  """
  def attrs_from_file(filename, body) do
    {meta, content} = split_frontmatter(body)

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

  # A leading `---` block, terminated by a `---` line. Tolerates CRLF line
  # endings and trailing spaces on the fence lines. A leading BOM is stripped
  # separately (see split_frontmatter/1) so this pattern stays ASCII-only.
  @frontmatter ~r/\A[ \t]*---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n?/s

  @doc """
  Split a leading YAML frontmatter block off `body`. Returns
  `{meta_map, remaining_body}`; `meta_map` is empty when there's no
  frontmatter and the body is returned untouched.
  """
  def split_frontmatter(body) when is_binary(body) do
    body = strip_bom(body)

    case Regex.run(@frontmatter, body) do
      [whole, yaml] ->
        rest = body |> String.replace_prefix(whole, "") |> String.trim_leading()
        {parse_meta(yaml), rest}

      _ ->
        {%{}, body}
    end
  end

  defp strip_bom("﻿" <> rest), do: rest
  defp strip_bom(body), do: body

  defp parse_meta(yaml) do
    yaml
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(~r/^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$/, line) do
        [_, key, value] -> Map.put(acc, String.downcase(key), unquote_value(value))
        _ -> acc
      end
    end)
  end

  defp unquote_value(value) do
    value |> String.trim() |> String.trim("\"") |> String.trim("'")
  end

  defp frontmatter_title(meta) do
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

  # Published when frontmatter explicitly says `draft: false`. No frontmatter,
  # no `draft` key, or `draft: true` all mean "keep it a draft".
  defp published?(meta) do
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
