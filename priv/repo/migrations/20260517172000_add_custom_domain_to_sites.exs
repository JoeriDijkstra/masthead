defmodule Masthead.Repo.Migrations.AddCustomDomainToSites do
  use Ecto.Migration

  def change do
    alter table(:sites) do
      add :custom_domain, :string
      add :custom_domain_status, :string, null: false, default: "unconfigured"
      add :custom_domain_token, :string
      add :custom_domain_verified_at, :utc_datetime
      add :custom_domain_last_checked_at, :utc_datetime
      add :custom_domain_last_error, :string
    end

    create unique_index(:sites, [:custom_domain])
  end
end
