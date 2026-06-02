defmodule Masthead.Repo.Migrations.AddMetadataToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      # Theme-scoped per-page metadata. Shape is driven by the active theme's
      # manifest `metadata` schema; unknown keys are preserved on save so
      # data survives theme switches.
      add :metadata, :map, null: false, default: %{}
    end
  end
end
