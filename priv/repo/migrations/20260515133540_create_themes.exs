defmodule Ledger.Repo.Migrations.CreateThemes do
  use Ecto.Migration

  def change do
    create table(:themes) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :description, :text, default: "", null: false
      add :version, :string, null: false
      add :source, :string, null: false
      add :owner_id, references(:users, on_delete: :nilify_all)
      add :storage_path, :string, null: false
      add :manifest, :map, null: false, default: %{}
      add :public, :boolean, null: false, default: false
      timestamps(type: :utc_datetime)
    end

    # System (built-in) slugs are globally unique.
    create unique_index(:themes, [:slug],
             where: "owner_id IS NULL",
             name: :themes_system_slug_index
           )

    # Per-owner slugs are unique within that owner.
    create unique_index(:themes, [:owner_id, :slug],
             where: "owner_id IS NOT NULL",
             name: :themes_owner_slug_index
           )

    create index(:themes, [:owner_id])
    create index(:themes, [:source])
  end
end
