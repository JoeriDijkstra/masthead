defmodule Ledger.Content.HTML.Scrubber do
  @moduledoc """
  Custom HTML scrubber for post and page bodies.

  Extends `HtmlSanitizeEx.Scrubber.MarkdownHTML` with the structural
  tags (`div`, `section`, `article`, `header`, ...) and `class` / `id`
  attributes required for users to publish full HTML pages styled by a
  theme's stylesheet.

  Markdown-rendered content doesn't emit these tags, so existing markdown
  pages render identically. The broadened surface only matters when a
  user pastes raw HTML into the page editor.

  What stays blocked:

    * `<script>`, `<style>`, `<iframe>`, `<object>`, `<embed>`, `<link>`, `<meta>`
    * `on*` event attributes
    * `javascript:` URLs (for `<a>`; `<img>` allows `data:` for inline images)
    * `style` attribute (we don't allow inline styles — themes own styling)
  """

  use HtmlSanitizeEx, extend: :strip_tags

  # ---- Structural / layout tags ----
  allow_tag_with_these_attributes("div", ["class", "id"])
  allow_tag_with_these_attributes("span", ["class", "id"])
  allow_tag_with_these_attributes("section", ["class", "id"])
  allow_tag_with_these_attributes("article", ["class", "id"])
  allow_tag_with_these_attributes("header", ["class", "id"])
  allow_tag_with_these_attributes("footer", ["class", "id"])
  allow_tag_with_these_attributes("nav", ["class", "id"])
  allow_tag_with_these_attributes("aside", ["class", "id"])
  allow_tag_with_these_attributes("figure", ["class", "id"])
  allow_tag_with_these_attributes("figcaption", ["class", "id"])
  allow_tag_with_these_attributes("main", ["class", "id"])

  # ---- Text + headings ----
  allow_tag_with_these_attributes("p", ["class", "id"])
  allow_tag_with_these_attributes("h1", ["class", "id"])
  allow_tag_with_these_attributes("h2", ["class", "id"])
  allow_tag_with_these_attributes("h3", ["class", "id"])
  allow_tag_with_these_attributes("h4", ["class", "id"])
  allow_tag_with_these_attributes("h5", ["class", "id"])
  allow_tag_with_these_attributes("h6", ["class", "id"])

  allow_tag_with_these_attributes("strong", ["class"])
  allow_tag_with_these_attributes("em", ["class"])
  allow_tag_with_these_attributes("b", ["class"])
  allow_tag_with_these_attributes("i", ["class"])
  allow_tag_with_these_attributes("u", ["class"])
  allow_tag_with_these_attributes("br", ["class"])
  allow_tag_with_these_attributes("hr", ["class"])
  allow_tag_with_these_attributes("small", ["class"])
  allow_tag_with_these_attributes("del", ["class"])
  allow_tag_with_these_attributes("s", ["class"])
  allow_tag_with_these_attributes("mark", ["class"])
  allow_tag_with_these_attributes("sub", ["class"])
  allow_tag_with_these_attributes("sup", ["class"])
  allow_tag_with_these_attributes("kbd", ["class"])

  # ---- Links — allowlist the schemes and attributes ----
  allow_tag_with_uri_attributes("a", ["href"], ["http", "https", "mailto", "tel"])
  allow_tag_with_these_attributes("a", ["title", "class", "id", "rel"])
  allow_tag_with_this_attribute_values("a", "target", ["_blank", "_self"])

  # ---- Time element (semantic dates) ----
  allow_tag_with_these_attributes("time", ["class", "id", "datetime"])

  # ---- Lists ----
  allow_tag_with_these_attributes("ul", ["class", "id"])
  allow_tag_with_these_attributes("ol", ["class", "id"])
  allow_tag_with_these_attributes("li", ["class", "id"])
  allow_tag_with_these_attributes("dl", ["class", "id"])
  allow_tag_with_these_attributes("dt", ["class", "id"])
  allow_tag_with_these_attributes("dd", ["class", "id"])

  # ---- Quotes + code ----
  allow_tag_with_these_attributes("blockquote", ["class", "id", "cite"])
  allow_tag_with_these_attributes("code", ["class"])
  allow_tag_with_these_attributes("pre", ["class"])

  # ---- Tables ----
  allow_tag_with_these_attributes("table", ["class", "id"])
  allow_tag_with_these_attributes("caption", ["class"])
  allow_tag_with_these_attributes("thead", ["class"])
  allow_tag_with_these_attributes("tbody", ["class"])
  allow_tag_with_these_attributes("tfoot", ["class"])
  allow_tag_with_these_attributes("tr", ["class"])
  allow_tag_with_these_attributes("th", ["class", "colspan", "rowspan", "scope"])
  allow_tag_with_these_attributes("td", ["class", "colspan", "rowspan"])

  # ---- Images ----
  allow_tag_with_these_attributes("img", [
    "alt",
    "title",
    "class",
    "id",
    "width",
    "height",
    "loading"
  ])

  allow_tag_with_uri_attributes("img", ["src"], ["http", "https", "data"])
end
