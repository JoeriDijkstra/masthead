defmodule MastheadWeb.UnsubscribeControllerTest do
  use MastheadWeb.ConnCase

  alias Masthead.Accounts
  alias Masthead.Accounts.User
  alias MastheadWeb.OnboardingToken

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "unsub-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  test "a valid token opts the user out of onboarding emails", %{conn: conn, user: user} do
    assert user.wants_onboarding_emails

    path = URI.parse(OnboardingToken.unsubscribe_url(user.id)).path
    conn = get(conn, path)

    assert html_response(conn, 200) =~ "unsubscribed"
    refute Masthead.Repo.get!(User, user.id).wants_onboarding_emails
  end

  test "an invalid token changes nothing", %{conn: conn, user: user} do
    conn = get(conn, ~p"/unsubscribe/onboarding/not-a-real-token")

    assert html_response(conn, 200) =~ "expired"
    assert Masthead.Repo.get!(User, user.id).wants_onboarding_emails
  end
end
