defmodule Ledger.Sites.Site do
  use Ecto.Schema
  import Ecto.Changeset

  @reserved_slugs ~w(www api app dashboard login signup logout auth public assets static help docs sites new themes)

  schema "sites" do
    field :slug, :string
    field :name, :string
    field :title, :string, default: ""
    field :description, :string, default: ""
    field :theme_tokens, :map, default: %{}
    field :theme_css_overrides, :string, default: ""
    belongs_to :owner, Ledger.Accounts.User
    belongs_to :theme_ref, Ledger.Themes.Theme, foreign_key: :theme_id
    belongs_to :homepage_page, Ledger.Content.Page, foreign_key: :homepage_page_id
    has_many :posts, Ledger.Content.Post
    has_many :pages, Ledger.Content.Page
    timestamps(type: :utc_datetime)
  end

  def create_changeset(site, attrs) do
    site
    |> cast(attrs, [:slug, :name, :title, :description, :theme_id, :owner_id])
    |> normalize_slug()
    |> validate_required([:slug, :name, :owner_id])
    |> validate_format(:slug, ~r/^[a-z0-9]([a-z0-9-]{0,30}[a-z0-9])?$/,
      message: "must be 1-32 chars, lowercase letters/digits/hyphens, no leading/trailing hyphen"
    )
    |> validate_exclusion(:slug, @reserved_slugs)
    |> validate_length(:name, max: 100)
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 1000)
    |> unique_constraint(:slug)
    |> assoc_constraint(:owner)
  end

  def settings_changeset(site, attrs) do
    attrs =
      attrs
      |> normalize_homepage_id()
      |> normalize_theme_tokens()

    site
    |> cast(attrs, [
      :name,
      :title,
      :description,
      :theme_id,
      :theme_tokens,
      :theme_css_overrides,
      :homepage_page_id
    ])
    |> validate_required([:name, :theme_id])
    |> validate_length(:name, max: 100)
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 1000)
    |> validate_length(:theme_css_overrides, max: 50_000)
    |> assoc_constraint(:theme_ref)
  end

  # Site settings is a flat HTML form, so token overrides come in as
  # `site[theme_tokens][<key>]` and arrive as a map of strings. Empty
  # strings mean "fall back to the manifest default" — strip those out
  # before storing so we don't pin the override to a blank value.
  defp normalize_theme_tokens(%{"theme_tokens" => tokens} = attrs) when is_map(tokens) do
    cleaned =
      tokens
      |> Enum.reject(fn {_, v} -> v == "" or is_nil(v) end)
      |> Map.new()

    Map.put(attrs, "theme_tokens", cleaned)
  end

  defp normalize_theme_tokens(attrs), do: attrs

  defp normalize_homepage_id(%{"homepage_page_id" => ""} = attrs),
    do: Map.put(attrs, "homepage_page_id", nil)

  defp normalize_homepage_id(attrs), do: attrs

  defp normalize_slug(changeset) do
    case get_change(changeset, :slug) do
      slug when is_binary(slug) ->
        put_change(changeset, :slug, String.downcase(String.trim(slug)))

      _ ->
        changeset
    end
  end
end
