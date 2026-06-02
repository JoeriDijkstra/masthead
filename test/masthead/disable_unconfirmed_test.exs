defmodule Masthead.DisableUnconfirmedTest do
  use Masthead.DataCase
  use Oban.Testing, repo: Masthead.Repo

  alias Masthead.Accounts
  alias Masthead.Accounts.User
  alias Masthead.Workers.DisableUnconfirmed

  defp user(prefix) do
    {:ok, u} =
      Accounts.register_user(%{
        "email" => "#{prefix}-#{System.unique_integer([:positive])}@example.com",
        "password" => "password1234"
      })

    u
  end

  defp backdate(user, days) do
    at =
      DateTime.utc_now()
      |> DateTime.add(-days * 24 * 60 * 60, :second)
      |> DateTime.truncate(:second)

    Repo.update_all(
      from(u in User, where: u.id == ^user.id),
      set: [inserted_at: at]
    )

    user
  end

  test "disables only unconfirmed accounts older than 7 days" do
    stale = user("stale") |> backdate(8)
    fresh = user("fresh") |> backdate(2)

    confirmed_old = user("conf")
    {:ok, _} = Accounts.confirm_user(Accounts.generate_email_token(confirmed_old, "confirm"))
    backdate(confirmed_old, 30)

    assert Accounts.disable_unconfirmed_accounts() == 1

    assert User.disabled?(Repo.reload(stale))
    refute User.disabled?(Repo.reload(fresh))
    refute User.disabled?(Repo.reload(confirmed_old))
  end

  test "skips accounts already disabled (idempotent, count excludes them)" do
    stale = user("stale") |> backdate(10)
    {:ok, _} = Accounts.disable_user(stale)

    assert Accounts.disable_unconfirmed_accounts() == 0
  end

  test "the Oban worker runs the sweep" do
    stale = user("stale") |> backdate(9)

    assert :ok = perform_job(DisableUnconfirmed, %{})
    assert User.disabled?(Repo.reload(stale))
  end
end
