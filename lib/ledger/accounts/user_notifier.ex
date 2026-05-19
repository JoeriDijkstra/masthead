defmodule Ledger.Accounts.UserNotifier do
  @moduledoc """
  Builds account emails and enqueues them via `Ledger.Workers.Email`
  (Oban) so delivery survives a transient provider failure.

  Callers pass a fully-built URL; this module does not know routes.
  """
  alias Ledger.Workers.Email

  @doc "Email confirmation link for a new (or unconfirmed) account."
  def deliver_confirmation_instructions(user, url) do
    deliver(user.email, "Confirm your Ledger account", """
    Hi,

    Welcome to Ledger. Confirm your account by visiting the link below:

    #{url}

    This link expires in 7 days. If you didn't create a Ledger account,
    you can safely ignore this email.
    """)
  end

  @doc "Password-reset link."
  def deliver_reset_password_instructions(user, url) do
    deliver(user.email, "Reset your Ledger password", """
    Hi,

    You (or someone) requested a password reset for your Ledger account.
    Choose a new password by visiting the link below:

    #{url}

    This link expires in 1 day. If you didn't request this, ignore this
    email — your password will not change.
    """)
  end

  # Enqueue rather than send inline so a flaky provider retries.
  defp deliver(to, subject, text_body) do
    %{
      to: to,
      subject: subject,
      text_body: text_body,
      html_body: text_to_html(text_body)
    }
    |> Email.new()
    |> Oban.insert()

    {:ok, %{to: to, subject: subject}}
  end

  defp text_to_html(text) do
    escaped =
      text
      |> String.replace("&", "&amp;")
      |> String.replace("<", "&lt;")
      |> String.replace(">", "&gt;")

    "<pre style=\"font-family:inherit;white-space:pre-wrap\">#{escaped}</pre>"
  end
end
