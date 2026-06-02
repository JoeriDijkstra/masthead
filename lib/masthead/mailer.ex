defmodule Masthead.Mailer do
  @moduledoc """
  Transactional mailer. Adapter is environment-specific (configured in
  `config/*.exs`): `Swoosh.Adapters.Local` in dev, `Swoosh.Adapters.Test`
  in test, `Swoosh.Adapters.Resend` in prod.

  Mail is not sent directly from request paths — `Masthead.Accounts.UserNotifier`
  enqueues an `Masthead.Workers.Email` Oban job so a transient provider failure
  retries instead of losing a confirmation/reset email.
  """
  use Swoosh.Mailer, otp_app: :masthead

  @doc """
  The `{name, address}` tuple all Masthead mail is sent from.
  Overridden in prod via the `MAIL_FROM` env var (see runtime.exs).
  """
  def from do
    Application.fetch_env!(:masthead, :mail_from)
  end
end
