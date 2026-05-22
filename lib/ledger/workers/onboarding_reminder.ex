defmodule Ledger.Workers.OnboardingReminder do
  @moduledoc """
  Daily cron sweep: for each site with reminder-eligible actions still open a
  week after they were created, send the owner a single reminder email and
  mark those actions reminded (so it never repeats). Actions are grouped by
  site so an owner gets one email per site, however many actions are due.
  """
  use Oban.Worker, queue: :mailers, max_attempts: 3

  alias Ledger.Actions
  alias Ledger.Accounts.UserNotifier
  alias LedgerWeb.OnboardingToken

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    emails =
      Actions.due_reminders()
      |> Enum.group_by(& &1.site_id)
      |> Enum.map(fn {_site_id, actions} -> remind_site(actions) end)
      |> Enum.sum()

    if emails > 0, do: Logger.info("OnboardingReminder: sent #{emails} reminder email(s)")
    :ok
  end

  defp remind_site(actions) do
    site = hd(actions).site
    owner = site.owner

    items =
      Enum.map(actions, fn action ->
        %{
          title: Actions.title(action),
          message: action.message,
          cta: Actions.cta(action),
          url: action_url(action)
        }
      end)

    UserNotifier.deliver_onboarding_reminder(
      owner.email,
      site.name,
      items,
      OnboardingToken.unsubscribe_url(owner.id)
    )

    Enum.each(actions, &Actions.mark_reminded/1)
    1
  end

  defp action_url(%{path: nil}), do: LedgerWeb.Endpoint.url()
  defp action_url(%{path: path}), do: LedgerWeb.Endpoint.url() <> path
end
