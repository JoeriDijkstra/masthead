defmodule Masthead.Themes.ThemeInstall do
  @moduledoc """
  Records that a user has installed a published marketplace theme into
  their library. Installed themes show up in the user's `/themes` list
  (with a green "Marketplace" chip) and become usable on their sites.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "theme_installs" do
    belongs_to :user, Masthead.Accounts.User
    belongs_to :theme, Masthead.Themes.Theme
    timestamps(type: :utc_datetime)
  end

  def changeset(install, attrs) do
    install
    |> cast(attrs, [:user_id, :theme_id])
    |> validate_required([:user_id, :theme_id])
    |> assoc_constraint(:user)
    |> assoc_constraint(:theme)
    |> unique_constraint([:user_id, :theme_id])
  end
end
