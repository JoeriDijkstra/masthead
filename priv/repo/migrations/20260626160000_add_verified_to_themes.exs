defmodule Masthead.Repo.Migrations.AddVerifiedToThemes do
  use Ecto.Migration

  def change do
    alter table(:themes) do
      add :verified, :boolean, null: false, default: false
    end

    # Marketplace lists published themes ordered verified-first; this index
    # supports the `public == true` filter + `verified` ordering.
    create index(:themes, [:public, :verified])
  end
end
