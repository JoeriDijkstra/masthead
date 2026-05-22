defmodule LedgerWeb.UnsubscribeController do
  use LedgerWeb, :controller

  alias Ledger.Accounts
  alias LedgerWeb.OnboardingToken

  @doc "One-click unsubscribe from onboarding/nudge emails. No login required."
  def onboarding(conn, %{"token" => token}) do
    case OnboardingToken.verify(token) do
      {:ok, user_id} ->
        Accounts.unsubscribe_onboarding_emails(user_id)
        render(conn, :onboarding, unsubscribed: true)

      {:error, _reason} ->
        render(conn, :onboarding, unsubscribed: false)
    end
  end
end
