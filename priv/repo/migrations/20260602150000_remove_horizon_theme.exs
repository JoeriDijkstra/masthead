defmodule Masthead.Repo.Migrations.RemoveHorizonTheme do
  use Ecto.Migration

  # "horizon" was a short-lived built-in that got folded into the new
  # "tailwind" theme before release. If it was ever seeded locally, reassign
  # any sites on it to the default theme and drop the orphaned row so it
  # doesn't linger in the theme picker with missing template files.
  def up do
    execute("""
    UPDATE sites
    SET theme_id = (
      SELECT id FROM themes WHERE slug = 'default' AND source = 'built_in' LIMIT 1
    )
    WHERE theme_id IN (
      SELECT id FROM themes WHERE slug = 'horizon' AND source = 'built_in'
    )
    """)

    execute("DELETE FROM themes WHERE slug = 'horizon' AND source = 'built_in'")
  end

  def down, do: :ok
end
