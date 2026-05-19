defmodule Ledger.Workers.DisableUnconfirmed do
  @moduledoc """
  Daily sweep (Oban cron) that disables accounts which never confirmed
  their email within 7 days of signing up — and, via the disable
  cascade, takes their sites offline. Re-enable is console/admin only.
  """
  use Oban.Worker, queue: :maintenance, max_attempts: 3

  require Logger

  alias Ledger.Accounts

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    case Accounts.disable_unconfirmed_accounts() do
      0 ->
        :ok

      n ->
        Logger.info("DisableUnconfirmed: disabled #{n} unconfirmed account(s)")
        :ok
    end
  end
end
