defmodule Masthead.Repo.Migrations.RemoveBlankTheme do
  use Ecto.Migration

  # The built-in "blank" theme has been retired in favour of "tailwind".
  # Reassign any sites still on it to the default theme, then drop the row.
  # (Built-in themes are seeded from priv/themes/ on boot, so the new
  # "tailwind" row is created there — this migration only cleans up "blank".)
  def up do
    execute("""
    UPDATE sites
    SET theme_id = (
      SELECT id FROM themes WHERE slug = 'default' AND source = 'built_in' LIMIT 1
    )
    WHERE theme_id IN (
      SELECT id FROM themes WHERE slug = 'blank' AND source = 'built_in'
    )
    """)

    execute("DELETE FROM themes WHERE slug = 'blank' AND source = 'built_in'")
  end

  # Irreversible: the blank theme's files are gone, so we can't recreate the
  # row meaningfully. No-op so rollbacks of later migrations don't fail.
  def down, do: :ok
end
