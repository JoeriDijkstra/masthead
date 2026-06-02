defmodule Masthead.Repo.Migrations.AddActionTitle do
  use Ecto.Migration

  # Custom (admin-authored) actions carry their own title text. Predefined
  # actions leave this null and derive their title from the key.
  def change do
    alter table(:actions) do
      add :title, :string
    end
  end
end
