defmodule Ledger.Content.Page do
  use Ecto.Schema
  import Ecto.Changeset

  schema "pages" do
    field :title, :string
    field :slug, :string
    field :body, :string, default: ""
    field :format, :string, default: "markdown"
    field :published, :boolean, default: false
    belongs_to :site, Ledger.Sites.Site
    timestamps(type: :utc_datetime)
  end

  def changeset(page, attrs) do
    page
    |> cast(attrs, [:title, :slug, :body, :format, :published, :site_id])
    |> validate_required([:title, :site_id])
    |> validate_inclusion(:format, ~w(markdown html blog))
    |> ensure_slug()
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,80}[a-z0-9])?$/,
      message: "lowercase letters, numbers, hyphens")
    |> unique_constraint([:site_id, :slug], name: :pages_site_id_slug_index)
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
end
