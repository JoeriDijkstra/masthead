defmodule Masthead.Repo.Migrations.CreateTags do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :color, :string
      timestamps(type: :utc_datetime)
    end

    create unique_index(:tags, [:site_id, :slug])
    create index(:tags, [:site_id])
  end
end
