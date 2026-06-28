defmodule Masthead.Content.Page do
  use Ecto.Schema
  import Ecto.Changeset
  import Masthead.Content.ChangesetHelpers, only: [ensure_slug: 2, validate_liquid_body: 1]

  schema "pages" do
    field :title, :string
    field :slug, :string
    field :body, :string, default: ""
    field :format, :string, default: "markdown"
    # For `theme`-format pages: the chosen template name from the theme's
    # templates/pages/ folder. nil for markdown/html pages.
    field :template, :string
    field :published, :boolean, default: false
    field :show_in_nav, :boolean, default: true
    field :metadata, :map, default: %{}
    belongs_to :site, Masthead.Sites.Site
    # Tags a "blog"-format page filters its post list by (empty = show all).
    # Pages are not taggable content; this is a render-time filter selection.
    many_to_many :filter_tags, Masthead.Content.Tag,
      join_through: "page_filter_tags",
      on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [
      :title,
      :slug,
      :body,
      :format,
      :template,
      :published,
      :show_in_nav,
      :metadata,
      :site_id
    ])
    |> validate_required([:title, :site_id])
    |> validate_inclusion(:format, ~w(markdown html theme))
    |> normalize_template()
    |> validate_liquid_body()
    |> ensure_slug(:title)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens"
    )
    |> normalize_metadata()
    |> unique_constraint([:site_id, :slug], name: :pages_site_id_slug_index)
    |> assoc_constraint(:site)
  end

  # A `theme` page must name a template; any other format never carries one
  # (so switching format can't leave a stale template behind).
  defp normalize_template(changeset) do
    case get_field(changeset, :format) do
      "theme" -> validate_required(changeset, [:template])
      _ -> put_change(changeset, :template, nil)
    end
  end

  # Form posts arrive as `metadata[<key>] => "..."`. Strip empty-string
  # values so the renderer falls back to the manifest default instead of
  # storing an empty override. Booleans come in as "true" / "on" / absent;
  # absent means "false" (HTML checkbox semantics) — keep them coerced as
  # strings here and let `Manifest.effective_metadata/2` coerce to the
  # declared type at render time. Unknown keys are preserved.
  defp normalize_metadata(changeset) do
    case get_change(changeset, :metadata) do
      m when is_map(m) ->
        cleaned =
          m
          |> Enum.reject(fn {_, v} -> v == "" or is_nil(v) end)
          |> Map.new()

        put_change(changeset, :metadata, cleaned)

      _ ->
        changeset
    end
  end
end
