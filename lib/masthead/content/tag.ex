defmodule Masthead.Content.Tag do
  use Ecto.Schema
  import Ecto.Changeset
  import Masthead.Content.ChangesetHelpers, only: [ensure_slug: 2]

  schema "tags" do
    field :name, :string
    field :slug, :string
    belongs_to :site, Masthead.Sites.Site
    many_to_many :posts, Masthead.Content.Post, join_through: "post_tags"
    timestamps(type: :utc_datetime)
  end

  def changeset(tag, attrs) do
    tag
    |> cast(attrs, [:name, :slug, :site_id])
    |> validate_required([:name, :site_id])
    |> ensure_slug(:name)
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens"
    )
    |> unique_constraint(:slug, name: :tags_site_id_slug_index)
    |> assoc_constraint(:site)
  end
end
