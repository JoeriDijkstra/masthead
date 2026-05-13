defmodule LedgerWeb.SessionController do
  use LedgerWeb, :controller

  alias Ledger.Accounts
  alias LedgerWeb.UserAuth

  def new(conn, _params) do
    render(conn, :new, error: nil, email: "")
  end

  def create(conn, %{"user" => %{"email" => email, "password" => password}}) do
    case Accounts.get_user_by_email_and_password(email, password) do
      nil ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "Invalid email or password", email: email)

      user ->
        UserAuth.log_in_user(conn, user)
    end
  end

  def delete(conn, _params) do
    UserAuth.log_out_user(conn)
  end
end
