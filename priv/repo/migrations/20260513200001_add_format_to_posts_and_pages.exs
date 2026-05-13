defmodule Ledger.Repo.Migrations.AddFormatToPostsAndPages do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :format, :string, null: false, default: "markdown"
    end

    alter table(:pages) do
      add :format, :string, null: false, default: "markdown"
    end
  end
end
