defmodule Masthead.Accounts.UserIdentity do
  @moduledoc """
  Links a `Masthead.Accounts.User` to an external OAuth identity
  (`provider` + `provider_uid`). One row per (provider, account); a user
  may have at most one identity per provider.
  """
  use Ecto.Schema

  import Ecto.Changeset

  schema "user_identities" do
    field :provider, :string
    field :provider_uid, :string
    belongs_to :user, Masthead.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(identity, attrs) do
    identity
    |> cast(attrs, [:user_id, :provider, :provider_uid])
    |> validate_required([:user_id, :provider, :provider_uid])
    |> unique_constraint([:provider, :provider_uid])
    |> unique_constraint([:user_id, :provider])
  end
end
