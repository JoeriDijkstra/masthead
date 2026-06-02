defmodule Masthead.Repo.Migrations.AddShowInNavToPages do
  use Ecto.Migration

  def change do
    alter table(:pages) do
      # Whether a published page appears in the theme's top navigation.
      # Platform-level (not theme metadata) so it works regardless of the
      # active theme and survives theme switches.
      add :show_in_nav, :boolean, null: false, default: true
    end
  end
end
