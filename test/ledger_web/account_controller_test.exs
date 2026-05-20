defmodule LedgerWeb.AccountControllerTest do
  use LedgerWeb.ConnCase

  alias Ledger.Accounts
  alias Ledger.Accounts.User
  alias Ledger.Repo

  defp new_user(attrs \\ %{}) do
    {:ok, user} =
      Accounts.register_user(
        Map.merge(
          %{
            "email" => "acc-#{System.unique_integer([:positive])}@example.com",
            "password" => "password1234"
          },
          attrs
        )
      )

    user
  end

  defp log_in(conn, user), do: Plug.Test.init_test_session(conn, %{user_id: user.id})

  test "GET /account requires auth", %{conn: conn} do
    assert redirected_to(get(conn, ~p"/account")) == ~p"/login"
  end

  test "GET /account shows the account page", %{conn: conn} do
    user = new_user()
    conn = conn |> log_in(user) |> get(~p"/account")
    assert html_response(conn, 200) =~ "Account"
    assert html_response(conn, 200) =~ user.email
  end

  describe "POST /account/password" do
    test "updates with correct current password", %{conn: conn} do
      user = new_user()

      conn =
        conn
        |> log_in(user)
        |> post(~p"/account/password", %{
          "current_password" => "password1234",
          "user" => %{"password" => "freshpass987"}
        })

      assert redirected_to(conn) == ~p"/account"
      assert Accounts.get_user_by_email_and_password(user.email, "freshpass987")
    end

    test "rejects a wrong current password", %{conn: conn} do
      user = new_user()

      conn =
        conn
        |> log_in(user)
        |> post(~p"/account/password", %{
          "current_password" => "wrongwrong",
          "user" => %{"password" => "freshpass987"}
        })

      assert html_response(conn, 422) =~ "Current password is incorrect"
      refute Accounts.get_user_by_email_and_password(user.email, "freshpass987")
    end
  end

  describe "POST /account/disable" do
    test "disables, logs out, and blocks re-login", %{conn: conn} do
      user = new_user()

      conn = conn |> log_in(user) |> post(~p"/account/disable")
      assert redirected_to(conn) == ~p"/login"
      refute get_session(conn, :user_id)
      assert User.disabled?(Repo.reload(user))

      # cannot sign back in
      login =
        post(build_conn(), ~p"/login", %{
          "user" => %{"email" => user.email, "password" => "password1234"}
        })

      assert html_response(login, 401) =~ "disabled"
    end
  end

  test "a disabled user's live session is treated as logged out", %{conn: conn} do
    user = new_user()
    {:ok, _} = Accounts.disable_user(user)

    conn = conn |> log_in(user) |> get(~p"/sites")
    assert redirected_to(conn) == ~p"/login"
  end
end
