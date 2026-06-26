defmodule Masthead.Repo.Migrations.CreateThemeInstalls do
  use Ecto.Migration

  def change do
    create table(:theme_installs) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :theme_id, references(:themes, on_delete: :delete_all), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:theme_installs, [:user_id, :theme_id])
    create index(:theme_installs, [:theme_id])
  end
end
