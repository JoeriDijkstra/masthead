defmodule Masthead.Repo.Migrations.CreateActions do
  use Ecto.Migration

  def change do
    create table(:actions) do
      add :key, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :message, :text
      add :priority, :integer, null: false, default: 0
      add :path, :string
      add :site_id, references(:sites, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    # An action is a "one-off" per site: at most one row per (site, key).
    create unique_index(:actions, [:site_id, :key])
    create index(:actions, [:site_id, :status, :priority])
  end
end
