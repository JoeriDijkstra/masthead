defmodule Ledger.Themes.CssSanitizer do
  @moduledoc """
  Last-line-of-defense scrubber for CSS that arrives via two
  user-controllable surfaces:

    * `sites.theme_css_overrides` — free-text CSS appended to the theme's
      stylesheet on every render.
    * `sites.theme_tokens[<key>]` — token values spliced into a
      `:root { --foo: <value> }` block.

  We're not parsing CSS — that would be over-engineering for a sanitizer.
  Instead we strip the small set of patterns that are obvious foot-guns
  in a `<style>` block:

    * `@import` (would let overrides reach off the install)
    * `expression(...)` (legacy IE; defensive only)
    * `url(javascript:...)` (JS in stylesheet URLs)
    * `</style>` (closing tag breaks out of the inline block)
    * `<script` (paranoia)

  Token values get a stricter treatment: braces, quotes, angle brackets,
  semicolons and newlines are stripped, since a token value is supposed
  to be a single CSS literal (`#fff`, `880px`, `Inter, sans-serif`) and
  never declarations or selectors.
  """

  @doc "Sanitize a `theme_css_overrides` blob. Empty / nil → empty string."
  @spec sanitize_overrides(String.t() | nil) :: String.t()
  def sanitize_overrides(nil), do: ""
  def sanitize_overrides(""), do: ""

  def sanitize_overrides(css) when is_binary(css) do
    Enum.reduce(bad_css_patterns(), css, fn {pattern, replacement}, acc ->
      Regex.replace(pattern, acc, replacement)
    end)
  end

  defp bad_css_patterns do
    [
      {~r/@import\s+[^;]+;?/i, ""},
      {~r/expression\s*\(/i, "/* expression( */"},
      {~r/url\s*\(\s*['"]?\s*javascript:/i, "url("},
      {~r{</\s*style\s*>}i, ""},
      {~r/<\s*script/i, ""}
    ]
  end

  @doc """
  Sanitize a single token value. Strips characters that would let a
  malicious token break out of `--key: <value>;`.
  """
  @spec sanitize_token_value(String.t() | nil) :: String.t()
  def sanitize_token_value(nil), do: ""

  def sanitize_token_value(value) when is_binary(value) do
    value
    |> String.replace(~r/[{}<>;"\r\n]/, "")
    |> String.trim()
  end

  def sanitize_token_value(other), do: sanitize_token_value(to_string(other))
end
