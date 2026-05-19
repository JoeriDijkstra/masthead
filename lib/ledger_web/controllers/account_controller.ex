defmodule LedgerWeb.AccountController do
  use LedgerWeb, :controller

  import Plug.Conn

  alias Ledger.Accounts

  def show(conn, _params) do
    render(conn, :show,
      user: conn.assigns.current_user,
      password_changeset: Accounts.change_user_password(conn.assigns.current_user)
    )
  end

  def update_password(conn, %{"current_password" => current, "user" => user_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_password(user, current, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password updated.")
        |> redirect(to: ~p"/account")

      {:error, :invalid_current_password} ->
        conn
        |> put_flash(:error, "Current password is incorrect.")
        |> put_status(:unprocessable_entity)
        |> render(:show,
          user: user,
          password_changeset: Accounts.change_user_password(user)
        )

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:show, user: user, password_changeset: changeset)
    end
  end

  # Self-serve disable. Cascades to the user's sites and logs them out.
  # Reversible only via console/admin (no self re-enable by design).
  def disable(conn, _params) do
    {:ok, _user} = Accounts.disable_user(conn.assigns.current_user)

    conn
    |> configure_session(renew: true)
    |> clear_session()
    |> put_flash(:info, "Your account and all its sites have been disabled.")
    |> redirect(to: ~p"/login")
  end
end
