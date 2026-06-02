defmodule Masthead.Repo.Migrations.CreateUserIdentities do
  use Ecto.Migration

  def change do
    create table(:user_identities) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :provider_uid, :string, null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_identities, [:provider, :provider_uid])
    create index(:user_identities, [:user_id])
    create unique_index(:user_identities, [:user_id, :provider])
  end
end
