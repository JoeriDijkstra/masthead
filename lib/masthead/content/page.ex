defmodule Masthead.Content.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    field :title, :string
    field :slug, :string
    field :body, :string, default: ""
    field :format, :string, default: "markdown"
    field :published, :boolean, default: false
    field :show_in_nav, :boolean, default: true
    field :metadata, :map, default: %{}
    belongs_to :site, Masthead.Sites.Site
    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :slug, :body, :format, :published, :show_in_nav, :metadata, :site_id])
    |> validate_required([:title, :site_id])
    |> validate_inclusion(:format, ~w(markdown html blog))
    |> ensure_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens"
    )
    |> normalize_metadata()
    |> unique_constraint([:site_id, :slug], name: :pages_site_id_slug_index)
    |> assoc_constraint(:site)
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

  defp ensure_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        put_change(changeset, :slug, Slug.slugify(slug))

      _ ->
        case get_field(changeset, :title) do
          title when is_binary(title) and title != "" ->
            put_change(changeset, :slug, Slug.slugify(title))

          _ ->
            changeset
        end
    end
  end
end
