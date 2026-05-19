defmodule Ledger.Repo.Migrations.AddAccountLifecycleColumns do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # null = unconfirmed; null = active (not disabled).
      add :confirmed_at, :utc_datetime
      add :disabled_at, :utc_datetime
    end

    alter table(:sites) do
      # Set/cleared by the owning account's disable cascade. The Subdomain
      # plug treats a non-null value as "site does not exist" (404).
      add :disabled_at, :utc_datetime
    end

    # Accounts that predate email confirmation are grandfathered in as
    # confirmed so the auto-disable sweep never locks out existing users.
    execute(
      "UPDATE users SET confirmed_at = now() WHERE confirmed_at IS NULL",
      "UPDATE users SET confirmed_at = NULL"
    )
  end
end
