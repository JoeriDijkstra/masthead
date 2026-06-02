defmodule Masthead.Repo.Migrations.AddAdminAndSiteSoftDelete do
  use Ecto.Migration

  def change do
    # Platform admins — can manage all users/sites/themes from the admin
    # overview. Granted via seeds/console (no self-serve promotion).
    alter table(:users) do
      add :admin, :boolean, null: false, default: false
    end

    # Soft-delete for sites: distinct from `disabled_at` (a reversible
    # pause). A soft-deleted site is hidden from its owner and the public,
    # but retained for admin recovery.
    alter table(:sites) do
      add :deleted_at, :utc_datetime
    end
  end
end
