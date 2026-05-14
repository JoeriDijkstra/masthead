defmodule LedgerWeb.UserAuth do
  @moduledoc """
  Session-based authentication. Intentionally minimal: a signed user id is
  stored in the cookie session; there is no separate tokens table, no
  remember-me, no email confirmation.
  """
  import Plug.Conn
  import Phoenix.Controller

  alias Ledger.Accounts

  @session_key :user_id

  def log_in_user(conn, user, params \\ %{}) do
    return_to = get_session(conn, :user_return_to)

    conn
    |> renew_session()
    |> put_session(@session_key, user.id)
    |> put_session(:live_socket_id, "users_sessions:#{user.id}")
    |> maybe_put_flash(params)
    |> redirect(to: return_to || "/sites")
  end

  def log_out_user(conn) do
    conn
    |> renew_session()
    |> redirect(to: "/")
  end

  def fetch_current_user(conn, _opts) do
    user_id = get_session(conn, @session_key)

    user =
      if user_id, do: safe_get_user(user_id)

    assign(conn, :current_user, user)
  end

  def require_authenticated_user(conn, _opts) do
    if conn.assigns[:current_user] do
      conn
    else
      conn
      |> put_session(:user_return_to, current_path(conn))
      |> Phoenix.Controller.put_flash(:error, "You must log in to access that page.")
      |> redirect(to: "/login")
      |> halt()
    end
  end

  def on_mount(:current_user, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> safe_get_user(id)
      end

    {:cont, Phoenix.Component.assign(socket, :current_user, user)}
  end

  def on_mount(:require_authenticated, _params, session, socket) do
    user =
      case session["user_id"] do
        nil -> nil
        id -> safe_get_user(id)
      end

    if user do
      {:cont, Phoenix.Component.assign(socket, :current_user, user)}
    else
      {:halt,
       socket
       |> Phoenix.LiveView.put_flash(:error, "You must log in to access that page.")
       |> Phoenix.LiveView.redirect(to: "/login")}
    end
  end

  defp safe_get_user(id) do
    try do
      Accounts.get_user!(id)
    rescue
      Ecto.NoResultsError -> nil
    end
  end

  defp renew_session(conn) do
    delete_csrf_token()

    conn
    |> configure_session(renew: true)
    |> clear_session()
  end

  defp maybe_put_flash(conn, %{"flash" => msg}), do: Phoenix.Controller.put_flash(conn, :info, msg)
  defp maybe_put_flash(conn, _), do: conn
end
