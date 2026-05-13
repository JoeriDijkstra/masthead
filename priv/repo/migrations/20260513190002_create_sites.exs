defmodule Ledger.Repo.Migrations.CreateSites do
  use Ecto.Migration

  def change do
    create table(:sites) do
      add :slug, :string, null: false
      add :name, :string, null: false
      add :title, :string, null: false, default: ""
      add :description, :text, null: false, default: ""
      add :theme, :string, null: false, default: "default"
      add :owner_id, references(:users, on_delete: :restrict), null: false
      timestamps(type: :utc_datetime)
    end

    create unique_index(:sites, [:slug])
    create index(:sites, [:owner_id])
  end
end
