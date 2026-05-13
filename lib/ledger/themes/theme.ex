defmodule Ledger.Themes.Theme do
  @moduledoc """
  Behaviour for themes.

  A theme is a single module that knows how to render each public page of a
  site. The module receives a normalised assigns map and returns a
  `Phoenix.LiveView.Rendered` struct (typically via `~H`).

  See `Ledger.Themes.Default` for a reference implementation.

  Note: themes receive a plain `assigns` map (not a Phoenix.LiveView socket).
  If a callback needs to compute extra values before the `~H` block, use
  `Map.merge(assigns, %{...})` — `Phoenix.Component.assign/3` will raise
  because it requires HEEx change-tracking context.

  Note: HEEx will NOT interpolate `{...}` inside `<style>` or `<script>`
  tags — those are HTML "raw text" elements. To inline CSS or JS, build
  the whole tag in a helper and interpolate the result:

      defp inline_styles do
        Phoenix.HTML.raw(["<style>", theme_css(), "</style>"])
      end

      # in the layout HEEx:
      {inline_styles()}
  """
  alias Phoenix.LiveView.Rendered

  @doc "Site landing page (list of recent posts)."
  @callback render_index(assigns :: map()) :: Rendered.t()

  @doc "A single blog post."
  @callback render_post(assigns :: map()) :: Rendered.t()

  @doc "A standalone page."
  @callback render_page(assigns :: map()) :: Rendered.t()

  @doc """
  A `blog`-format page: the page's body is rendered as a Markdown intro,
  followed by the site's published post list. Assigns: `site`, `page`,
  `posts`, `body_html`, `pages`.
  """
  @callback render_blog(assigns :: map()) :: Rendered.t()

  @doc "404 for the site."
  @callback render_not_found(assigns :: map()) :: Rendered.t()
end
