defmodule MastheadWeb.OnboardingToken do
  @moduledoc """
  Signed, stateless tokens for the one-click "unsubscribe from onboarding
  emails" link. Uses `Phoenix.Token` (no DB row needed) — unsubscribing is
  idempotent, so single-use semantics aren't required. Long-lived so the link
  keeps working well after the email was sent.
  """
  use MastheadWeb, :verified_routes

  @salt "onboarding-unsubscribe"
  @max_age 60 * 60 * 24 * 90

  @doc "Absolute one-click unsubscribe URL for `user_id`."
  def unsubscribe_url(user_id) do
    token = Phoenix.Token.sign(MastheadWeb.Endpoint, @salt, user_id)
    url(~p"/unsubscribe/onboarding/#{token}")
  end

  @doc "Verifies a token, returning `{:ok, user_id}` or `{:error, reason}`."
  def verify(token) do
    Phoenix.Token.verify(MastheadWeb.Endpoint, @salt, token, max_age: @max_age)
  end
end
