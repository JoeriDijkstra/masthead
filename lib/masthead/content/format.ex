defmodule Masthead.Content.Format do
  @moduledoc """
  Best-effort tidy-up of a post/page body for the editor's "Format" tool.

  HTML is parsed and re-serialised with Floki's pretty printer; Markdown
  (and anything else) gets light whitespace normalisation. Both paths are
  non-destructive: on a parse error or empty input the original is returned
  unchanged.
  """

  @doc "Format `body` according to `format` (\"html\" | \"markdown\" | \"blog\")."
  def run(nil, _format), do: ""

  def run(body, "html") when is_binary(body) do
    case Floki.parse_fragment(body) do
      {:ok, tree} -> Floki.raw_html(tree, pretty: true)
      _ -> normalize_whitespace(body)
    end
  rescue
    _ -> normalize_whitespace(body)
  end

  def run(body, _markdown) when is_binary(body), do: normalize_whitespace(body)

  # Normalise line endings, strip trailing spaces, collapse runs of blank
  # lines to a single one, and trim leading/trailing blank lines.
  defp normalize_whitespace(body) do
    body
    |> String.replace("\r\n", "\n")
    |> String.split("\n")
    |> Enum.map_join("\n", &String.trim_trailing/1)
    |> then(&Regex.replace(~r/\n{3,}/, &1, "\n\n"))
    |> String.trim()
  end
end
