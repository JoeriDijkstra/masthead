defmodule Masthead.Repo.Migrations.CreatePages do
  use Ecto.Migration

  def change do
    create table(:pages) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :slug, :string, null: false
      add :body, :text, null: false, default: ""
      add :published, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:pages, [:site_id, :slug])
  end
end
