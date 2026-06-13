defmodule Masthead.Content.Post do
  use Ecto.Schema
  import Ecto.Changeset

  schema "posts" do
    field :title, :string
    field :slug, :string
    field :body, :string, default: ""
    field :excerpt, :string, default: ""
    field :format, :string, default: "markdown"
    field :published, :boolean, default: false
    field :published_at, :utc_datetime
    belongs_to :site, Masthead.Sites.Site
    many_to_many :tags, Masthead.Content.Tag, join_through: "post_tags", on_replace: :delete
    timestamps(type: :utc_datetime)
  end

  def changeset(post, attrs) do
    post
    |> cast(attrs, [:title, :slug, :body, :excerpt, :format, :published, :site_id])
    |> validate_required([:title, :site_id])
    |> validate_inclusion(:format, ~w(markdown html))
    |> ensure_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens"
    )
    |> set_published_at()
    |> unique_constraint([:site_id, :slug], name: :posts_site_id_slug_index)
    |> assoc_constraint(:site)
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

  defp set_published_at(changeset) do
    published = get_field(changeset, :published)
    at = get_field(changeset, :published_at)

    cond do
      published && is_nil(at) ->
        put_change(changeset, :published_at, DateTime.utc_now() |> DateTime.truncate(:second))

      !published ->
        changeset

      true ->
        changeset
    end
  end
end
