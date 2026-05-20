defmodule LedgerWeb.ConfirmationControllerTest do
  use LedgerWeb.ConnCase
  use Oban.Testing, repo: Ledger.Repo

  alias Ledger.Accounts
  alias Ledger.Accounts.User
  alias Ledger.Repo

  defp new_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "cc-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    user
  end

  defp log_in(conn, user) do
    Plug.Test.init_test_session(conn, %{user_id: user.id})
  end

  describe "POST /signup" do
    test "creates an unconfirmed user, logs in, and enqueues confirmation", %{conn: conn} do
      email = "signup-#{System.unique_integer([:positive])}@example.com"

      conn =
        post(conn, ~p"/signup", %{
          "user" => %{"email" => email, "password" => "password1234"}
        })

      assert redirected_to(conn) == ~p"/sites"
      assert get_session(conn, :user_id)
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "confirm"

      user = Accounts.get_user_by_email(email)
      refute User.confirmed?(user)
      assert_enqueued(worker: Ledger.Workers.Email, args: %{"to" => email})
    end
  end

  describe "GET /confirm/:token" do
    test "confirms a valid token", %{conn: conn} do
      user = new_user()
      token = Accounts.generate_email_token(user, "confirm")

      conn = get(conn, ~p"/confirm/#{token}")

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "confirmed"
      assert User.confirmed?(Repo.reload(user))
    end

    test "rejects an invalid token without confirming anyone", %{conn: conn} do
      user = new_user()
      conn = get(conn, ~p"/confirm/nope")

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
      refute User.confirmed?(Repo.reload(user))
    end

    test "logged-in user lands back on /sites", %{conn: conn} do
      user = new_user()
      token = Accounts.generate_email_token(user, "confirm")

      conn = conn |> log_in(user) |> get(~p"/confirm/#{token}")
      assert redirected_to(conn) == ~p"/sites"
    end
  end

  describe "POST /confirm (resend)" do
    test "enqueues a fresh email for a logged-in unconfirmed user", %{conn: conn} do
      user = new_user()

      conn = conn |> log_in(user) |> post(~p"/confirm")

      assert redirected_to(conn) == ~p"/sites"
      assert_enqueued(worker: Ledger.Workers.Email, args: %{"to" => user.email})
    end

    test "is harmless when logged out (enumeration-safe)", %{conn: conn} do
      conn = post(conn, ~p"/confirm")
      assert redirected_to(conn) == ~p"/login"
      refute_enqueued(worker: Ledger.Workers.Email)
    end
  end
end
