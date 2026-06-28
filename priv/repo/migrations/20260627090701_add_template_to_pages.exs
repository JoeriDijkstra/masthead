defmodule Masthead.Repo.Migrations.AddTemplateToPages do
  use Ecto.Migration

  # Theme pages pick a Liquid template from the theme's templates/pages/ folder;
  # the chosen name is stored here. The old hardcoded "blog" format becomes a
  # theme page pointing at the "blog" template.
  def up do
    alter table(:pages) do
      add :template, :string
    end

    execute "UPDATE pages SET format = 'theme', template = 'blog' WHERE format = 'blog'"
  end

  def down do
    execute "UPDATE pages SET format = 'blog', template = NULL WHERE format = 'theme' AND template = 'blog'"

    alter table(:pages) do
      remove :template
    end
  end
end
