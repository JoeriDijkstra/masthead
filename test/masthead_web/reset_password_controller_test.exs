defmodule MastheadWeb.ResetPasswordControllerTest do
  use MastheadWeb.ConnCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.Accounts

  defp new_user do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "rpc-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    user
  end

  describe "POST /reset-password" do
    test "known email: sends a link, generic flash", %{conn: conn} do
      user = new_user()
      conn = post(conn, ~p"/reset-password", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset link"
      assert_enqueued(worker: Masthead.Workers.Email, args: %{"to" => user.email})
    end

    test "unknown email: same flash, no mail (enumeration-safe)", %{conn: conn} do
      conn =
        post(conn, ~p"/reset-password", %{"user" => %{"email" => "nobody@example.com"}})

      assert redirected_to(conn) == ~p"/login"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "reset link"
      refute_enqueued(worker: Masthead.Workers.Email)
    end
  end

  describe "GET /reset-password/:token" do
    test "valid token renders the form", %{conn: conn} do
      user = new_user()
      token = Accounts.generate_email_token(user, "reset_password")

      conn = get(conn, ~p"/reset-password/#{token}")
      assert html_response(conn, 200) =~ "Choose a new password"
    end

    test "invalid token redirects back to request", %{conn: conn} do
      conn = get(conn, ~p"/reset-password/bogus")
      assert redirected_to(conn) == ~p"/reset-password"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "invalid or has expired"
    end
  end

  describe "PUT /reset-password/:token" do
    test "valid token + password updates and redirects to login", %{conn: conn} do
      user = new_user()
      token = Accounts.generate_email_token(user, "reset_password")

      conn =
        put(conn, ~p"/reset-password/#{token}", %{
          "user" => %{"password" => "brandnewpass1"}
        })

      assert redirected_to(conn) == ~p"/login"
      assert Accounts.get_user_by_email_and_password(user.email, "brandnewpass1")
    end

    test "too-short password re-renders with errors", %{conn: conn} do
      user = new_user()
      token = Accounts.generate_email_token(user, "reset_password")

      conn =
        put(conn, ~p"/reset-password/#{token}", %{"user" => %{"password" => "x"}})

      assert html_response(conn, 422) =~ "should be at least 8"
    end
  end
end
