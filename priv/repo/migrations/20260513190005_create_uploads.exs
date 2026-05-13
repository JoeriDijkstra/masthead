defmodule Ledger.Repo.Migrations.CreateUploads do
  use Ecto.Migration

  def change do
    create table(:uploads) do
      add :site_id, references(:sites, on_delete: :delete_all), null: false
      add :filename, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :bigint, null: false
      add :path, :string, null: false
      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:uploads, [:site_id])
  end
end
