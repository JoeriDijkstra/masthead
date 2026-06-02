defmodule Masthead.Content.HTML do
  @moduledoc """
  HTML sanitizer for post and page bodies.

  Single source of truth for what authors can put in their content. We
  use `Masthead.Content.HTML.Scrubber` — built on top of html_sanitize_ex's
  markdown allowlist but widened with the structural tags (`<div>`,
  `<section>`, `<article>`, ...) and `class` / `id` attributes that
  HTML-format pages need in order to use a theme's CSS.

  Markdown-rendered content doesn't emit those tags, so the broader
  surface is invisible to markdown authors — existing posts render
  identically.

  What stays blocked: `<script>`, `<style>`, `<iframe>`, `on*` event
  handlers, `javascript:` URLs, and the `style` attribute. Themes own
  styling; inline styles are not a supported authoring surface.
  """

  @doc "Sanitize a binary of HTML. Always returns a binary."
  def sanitize(nil), do: ""

  def sanitize(html) when is_binary(html) do
    # `use HtmlSanitizeEx, extend: ...` injects `sanitize/1` on the
    # scrubber module — *not* `scrub/1` (which is the per-node callback).
    Masthead.Content.HTML.Scrubber.sanitize(html)
  end
end
