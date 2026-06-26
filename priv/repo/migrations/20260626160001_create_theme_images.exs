defmodule Masthead.Repo.Migrations.CreateThemeImages do
  use Ecto.Migration

  def change do
    create table(:theme_images) do
      add :theme_id, references(:themes, on_delete: :delete_all), null: false
      add :storage_path, :string, null: false
      add :position, :integer, null: false, default: 0
      timestamps(type: :utc_datetime)
    end

    create index(:theme_images, [:theme_id])
    create index(:theme_images, [:theme_id, :position])
  end
end
