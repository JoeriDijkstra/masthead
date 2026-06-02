defmodule Masthead.AccountsResetPasswordTest do
  use Masthead.DataCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.Accounts
  alias Masthead.Accounts.User

  setup do
    {:ok, user} =
      Accounts.register_user(%{
        "email" => "rp-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    %{user: user}
  end

  test "deliver_user_reset_password_instructions enqueues mail + a reset token",
       %{user: user} do
    assert {:ok, _} =
             Accounts.deliver_user_reset_password_instructions(
               user,
               &"http://x/#{&1}"
             )

    assert_enqueued(worker: Masthead.Workers.Email, args: %{"to" => user.email})

    assert Repo.exists?(
             from t in Masthead.Accounts.UserToken,
               where: t.user_id == ^user.id and t.context == "reset_password"
           )
  end

  test "get_user_by_reset_password_token resolves a valid token", %{user: user} do
    token = Accounts.generate_email_token(user, "reset_password")
    assert %{id: id} = Accounts.get_user_by_reset_password_token(token)
    assert id == user.id
  end

  test "reset_user_password sets the new password and revokes all tokens",
       %{user: user} do
    confirm_token = Accounts.generate_email_token(user, "confirm")
    reset = Accounts.generate_email_token(user, "reset_password")

    assert {:ok, _updated} =
             Accounts.reset_user_password(user, %{"password" => "newpassword99"})

    assert Accounts.get_user_by_email_and_password(user.email, "newpassword99")
    refute Accounts.get_user_by_email_and_password(user.email, "password1234")

    # every token revoked (single-use + confirm killed too)
    refute Accounts.get_user_by_reset_password_token(reset)
    assert :error = Accounts.confirm_user(confirm_token)
  end

  test "reset_user_password also confirms an unconfirmed account", %{user: user} do
    refute User.confirmed?(user)
    assert {:ok, updated} = Accounts.reset_user_password(user, %{"password" => "newpassword99"})
    assert User.confirmed?(updated)
  end

  test "reset_user_password rejects a too-short password", %{user: user} do
    assert {:error, changeset} = Accounts.reset_user_password(user, %{"password" => "short"})
    assert %{password: ["should be at least 8 character(s)"]} = errors_on(changeset)
  end
end
