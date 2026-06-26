defmodule Masthead.Themes.TagPosts do
  @moduledoc """
  A lazily-resolved, tag-keyed collection of posts exposed to templates as
  `posts_by_tag`. Accessing a key runs a real, site-scoped DB query for that
  one tag and returns the projected post list:

      {% assign emacs = posts_by_tag["emacs"] %}
      {% for post in emacs %} ... {% endfor %}

  Only the tags a template actually references are queried — unlike the
  `posts` variable (every published post, preloaded once per request).

  The struct carries a `resolver` function (`slug -> [post_map]`) built by the
  renderer, so the query/projection lives in the content+renderer layer and
  this stays a thin sandbox-facing value. The renderer's resolver memoizes per
  request, so referencing the same tag more than once in a template doesn't
  re-query.
  """

  @enforce_keys [:resolver]
  defstruct resolver: nil
end

defimpl Solid.Matcher, for: Masthead.Themes.TagPosts do
  alias Masthead.Themes.TagPosts

  # A bare `{{ posts_by_tag }}` reference has no useful scalar value.
  def match(%TagPosts{}, []), do: {:ok, nil}

  # `posts_by_tag["emacs"]` / `posts_by_tag.emacs` -> the tag's post list,
  # with any trailing access (`.size`, `[0]`, ...) delegated to the List impl.
  def match(%TagPosts{resolver: resolver}, [slug | rest]) when is_binary(slug) do
    @protocol.match(resolver.(slug), rest)
  end

  def match(_data, _keys), do: {:error, :not_found}
end
