defmodule LedgerWeb.RegistrationController do
  use LedgerWeb, :controller

  alias Ledger.Accounts
  alias LedgerWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%Ledger.Accounts.User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        UserAuth.log_in_user(conn, user)

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new, changeset: changeset)
    end
  end
end
