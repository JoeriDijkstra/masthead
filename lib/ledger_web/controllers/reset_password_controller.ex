defmodule LedgerWeb.ResetPasswordController do
  use LedgerWeb, :controller

  alias Ledger.Accounts

  plug :load_user_from_token when action in [:edit, :update]

  # GET /reset-password — request form.
  def new(conn, _params), do: render(conn, :new)

  # POST /reset-password — enumeration-safe: identical response whether or
  # not the address has an account.
  def create(conn, %{"user" => %{"email" => email}}) do
    if user = Accounts.get_user_by_email(email) do
      Accounts.deliver_user_reset_password_instructions(
        user,
        &url(~p"/reset-password/#{&1}")
      )
    end

    conn
    |> put_flash(:info, "If that email has an account, a reset link is on its way.")
    |> redirect(to: ~p"/login")
  end

  # GET /reset-password/:token — set-new-password form.
  def edit(conn, _params) do
    render(conn, :edit,
      changeset: Accounts.change_user_password(conn.assigns.user),
      token: conn.assigns.token
    )
  end

  # PUT /reset-password/:token
  def update(conn, %{"user" => user_params}) do
    case Accounts.reset_user_password(conn.assigns.user, user_params) do
      {:ok, _user} ->
        conn
        |> put_flash(:info, "Password updated. Please sign in.")
        |> redirect(to: ~p"/login")

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:edit, changeset: changeset, token: conn.assigns.token)
    end
  end

  defp load_user_from_token(conn, _opts) do
    token = conn.params["token"]

    case token && Accounts.get_user_by_reset_password_token(token) do
      nil ->
        conn
        |> put_flash(:error, "That reset link is invalid or has expired.")
        |> redirect(to: ~p"/reset-password")
        |> halt()

      user ->
        conn |> assign(:user, user) |> assign(:token, token)
    end
  end
end
