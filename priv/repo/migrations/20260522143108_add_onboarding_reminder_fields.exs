defmodule Masthead.Repo.Migrations.AddOnboardingReminderFields do
  use Ecto.Migration

  def change do
    # One-shot reminder bookkeeping: set when the reminder email goes out so
    # we never email about the same action twice.
    alter table(:actions) do
      add :reminded_at, :utc_datetime
    end

    # Per-user opt-out for onboarding/nudge emails (one-click unsubscribe).
    alter table(:users) do
      add :wants_onboarding_emails, :boolean, null: false, default: true
    end
  end
end
