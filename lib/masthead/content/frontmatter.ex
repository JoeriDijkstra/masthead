defmodule Masthead.Content.Frontmatter do
  @moduledoc """
  Splits a leading frontmatter block off a document and returns
  `{meta_map, body}`.

  Supports YAML (`---`) and TOML (`+++`) fences — the two Hugo/Jekyll defaults.
  Only the flat `key: value` / `key = value` subset is parsed (downcased string
  keys, string values), which covers the fields content import needs (title,
  draft, slug, date). Nested maps, lists, and multi-line values are ignored.
  A leading BOM is tolerated, as are CRLF line endings.
  """

  @yaml ~r/\A[ \t]*---[ \t]*\r?\n(.*?)\r?\n---[ \t]*\r?\n?/s
  @toml ~r/\A[ \t]*\+\+\+[ \t]*\r?\n(.*?)\r?\n\+\+\+[ \t]*\r?\n?/s

  @yaml_line ~r/^\s*([A-Za-z0-9_-]+)\s*:\s*(.*)$/
  @toml_line ~r/^\s*([A-Za-z0-9_-]+)\s*=\s*(.*)$/

  @doc """
  Returns `{meta, body}`. `meta` is empty and `body` is returned untouched
  when there is no recognised frontmatter fence at the very start.
  """
  def split(body) when is_binary(body) do
    body = strip_bom(body)

    cond do
      match = Regex.run(@yaml, body) -> build(match, body, @yaml_line)
      match = Regex.run(@toml, body) -> build(match, body, @toml_line)
      true -> {%{}, body}
    end
  end

  defp build([whole, block], body, line_regex) do
    rest = body |> String.replace_prefix(whole, "") |> String.trim_leading()
    {parse(block, line_regex), rest}
  end

  defp parse(block, line_regex) do
    block
    |> String.split("\n")
    |> Enum.reduce(%{}, fn line, acc ->
      case Regex.run(line_regex, line) do
        [_, key, value] -> Map.put(acc, String.downcase(key), unquote_value(value))
        _ -> acc
      end
    end)
  end

  defp unquote_value(value) do
    value |> String.trim() |> String.trim("\"") |> String.trim("'")
  end

  defp strip_bom("﻿" <> rest), do: rest
  defp strip_bom(body), do: body
end
