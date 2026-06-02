defmodule Masthead.Repo.Migrations.CreatePosts do
  use Ecto.Migration

  def change do
    create table(:posts) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :title, :string, null: false
      add :slug, :string, null: false
      add :body, :text, null: false, default: ""
      add :excerpt, :text, null: false, default: ""
      add :published, :boolean, null: false, default: false
      add :published_at, :utc_datetime
      timestamps(type: :utc_datetime)
    end

    create unique_index(:posts, [:site_id, :slug])
    create index(:posts, [:site_id, :published, :published_at])
  end
end
