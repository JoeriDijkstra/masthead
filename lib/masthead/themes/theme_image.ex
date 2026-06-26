defmodule Masthead.Themes.ThemeImage do
  @moduledoc """
  A preview image in a theme's marketplace gallery.

  The bytes live in `Masthead.Storage` (under the `theme-previews`
  namespace); this row holds the relative `storage_path` and a `position`
  used to order the gallery.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "theme_images" do
    field :storage_path, :string
    field :position, :integer, default: 0
    belongs_to :theme, Masthead.Themes.Theme
    timestamps(type: :utc_datetime)
  end

  def changeset(image, attrs) do
    image
    |> cast(attrs, [:storage_path, :position, :theme_id])
    |> validate_required([:storage_path, :theme_id])
    |> assoc_constraint(:theme)
  end
end
