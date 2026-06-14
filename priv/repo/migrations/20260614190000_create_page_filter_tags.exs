defmodule Masthead.Repo.Migrations.CreatePageFilterTags do
  use Ecto.Migration

  def change do
    create table(:page_filter_tags) do
      add :page_id, references(:pages, on_delete: :delete_all), null: false
      add :tag_id, references(:tags, on_delete: :delete_all), null: false
    end

    create unique_index(:page_filter_tags, [:page_id, :tag_id])
    create index(:page_filter_tags, [:tag_id])
  end
end
