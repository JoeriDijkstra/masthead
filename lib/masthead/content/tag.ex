defmodule Masthead.Content.Tag do
  use Ecto.Schema
  import Ecto.Changeset

  schema "tags" do
    field :name, :string
    field :slug, :string
    field :color, :string
    belongs_to :site, Masthead.Sites.Site
    many_to_many :posts, Masthead.Content.Post, join_through: "post_tags"
    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :slug, :color, :site_id])
    |> validate_required([:name, :site_id])
    |> ensure_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens"
    )
    |> normalize_color()
    |> validate_format(:color, ~r/^#[0-9a-fA-F]{6}$/, message: "must be a hex color like #3b82f6")
    |> unique_constraint(:slug, name: :tags_site_id_slug_index)
    |> assoc_constraint(:site)
  end

  defp ensure_slug(changeset) do
    case get_field(changeset, :slug) do
      slug when is_binary(slug) and slug != "" ->
        put_change(changeset, :slug, Slug.slugify(slug))

      _ ->
        case get_field(changeset, :name) do
          name when is_binary(name) and name != "" ->
            put_change(changeset, :slug, Slug.slugify(name))

          _ ->
            changeset
        end
    end
  end

  # Treat a blank color as "no color" so the optional field can be cleared
  # without tripping the hex format validation.
  defp normalize_color(changeset) do
    case get_change(changeset, :color) do
      "" -> put_change(changeset, :color, nil)
      _ -> changeset
    end
  end
end
