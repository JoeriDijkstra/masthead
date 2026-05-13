defmodule Ledger.Repo.Migrations.AddHomepageToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :homepage_page_id, references(:pages, on_delete: :nilify_all)
    end

    create index(:sites, [:homepage_page_id])
  end
end
