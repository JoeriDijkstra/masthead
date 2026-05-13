defmodule Ledger.Content.HTML do
  @moduledoc """
  HTML sanitizer for post and page bodies.

  Single source of truth for what authors can put in their content. We use
  `HtmlSanitizeEx.markdown_html/1` as a starting point — it allows the tag
  set that markdown engines typically produce (headings, lists, links,
  images, code, blockquotes, tables) and strips everything dangerous
  (scripts, `on*` event handlers, `javascript:` URLs, unknown tags).

  Apply this to both Markdown-rendered output and raw author HTML, so
  there is exactly one allowlist regardless of input format.
  """

  @doc "Sanitize a binary of HTML. Always returns a binary."
  def sanitize(nil), do: ""
  def sanitize(html) when is_binary(html), do: HtmlSanitizeEx.markdown_html(html)
end
