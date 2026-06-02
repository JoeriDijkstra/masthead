defmodule MastheadWeb.RegistrationController do
  use MastheadWeb, :controller

  alias Masthead.Accounts
  alias MastheadWeb.UserAuth

  def new(conn, _params) do
    changeset = Accounts.change_user_registration(%Masthead.Accounts.User{})
    render(conn, :new, changeset: changeset)
  end

  def create(conn, %{"user" => user_params}) do
    case Accounts.register_user(user_params) do
      {:ok, user} ->
        Accounts.deliver_user_confirmation_instructions(
          user,
          &url(~p"/confirm/#{&1}")
        )

        UserAuth.log_in_user(conn, user, %{
          "flash" => "Account created. Check your email to confirm it."
        })

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> render(:new, changeset: changeset)
    end
  end
end
