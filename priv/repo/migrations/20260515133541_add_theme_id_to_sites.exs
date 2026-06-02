defmodule Masthead.Repo.Migrations.AddThemeIdToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      # Nullable for now — Phase 2 backfills from the legacy `theme` string
      # and then drops the old column in a follow-up migration that also
      # makes this NOT NULL.
      add :theme_id, references(:themes, on_delete: :restrict)
      add :theme_tokens, :map, null: false, default: %{}
      add :theme_css_overrides, :text, null: false, default: ""
    end

    create index(:sites, [:theme_id])
  end
end
