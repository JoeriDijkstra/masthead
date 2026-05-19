defmodule Ledger.Accounts do
  alias Ledger.Repo
  alias Ledger.Accounts.User
  alias Ledger.Accounts.UserToken
  alias Ledger.Accounts.UserNotifier
  alias Ledger.Sites

  def get_user!(id), do: Repo.get!(User, id)

  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = get_user_by_email(email)
    if User.valid_password?(user, password), do: user
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  def change_user_registration(%User{} = user, attrs \\ %{}) do
    User.registration_changeset(user, attrs)
  end

  ## Email tokens

  @doc """
  Builds a token for `user` in `context`, persists its hash, and returns
  the raw token to embed in an email link.
  """
  def generate_email_token(%User{} = user, context) do
    {raw_token, user_token} = UserToken.build_email_token(user, context)
    Repo.insert!(user_token)
    raw_token
  end

  @doc """
  Resolves a raw token to its user if the token is valid, the right
  context, and not expired. Returns `nil` otherwise.
  """
  def get_user_by_token(raw_token, context)
      when is_binary(raw_token) and is_binary(context) do
    case UserToken.verify_email_token_query(raw_token, context) do
      {:ok, query} -> Repo.one(query)
      :error -> nil
    end
  end

  def get_user_by_token(_, _), do: nil

  @doc """
  Deletes `user`'s tokens. `contexts` is a list of context strings or
  `:all`. Used to make tokens single-use and to revoke on disable.
  """
  def delete_user_tokens(%User{} = user, contexts) do
    Repo.delete_all(UserToken.by_user_and_contexts_query(user, contexts))
  end

  ## Email confirmation

  @doc """
  Sends a confirmation link. `url_fun` turns a raw token into the full
  confirmation URL. No-op (`{:error, :already_confirmed}`) if the email
  is already confirmed.
  """
  def deliver_user_confirmation_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    if User.confirmed?(user) do
      {:error, :already_confirmed}
    else
      token = generate_email_token(user, "confirm")
      UserNotifier.deliver_confirmation_instructions(user, url_fun.(token))
    end
  end

  @doc """
  Confirms the account behind `token`. Marks the email confirmed and
  burns every outstanding confirm token (single-use). `:error` if the
  token is invalid or expired.
  """
  def confirm_user(token) when is_binary(token) do
    with %User{} = user <- get_user_by_token(token, "confirm"),
         {:ok, %{user: user}} <- Repo.transaction(confirm_user_multi(user)) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  defp confirm_user_multi(user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.confirm_changeset(user))
    |> Ecto.Multi.delete_all(
      :tokens,
      UserToken.by_user_and_contexts_query(user, ["confirm"])
    )
  end

  ## Password reset

  @doc "Changeset for the set-new-password form."
  def change_user_password(%User{} = user, attrs \\ %{}) do
    User.password_changeset(user, attrs)
  end

  @doc """
  Sends a reset link. `url_fun` turns a raw token into the full URL.
  Callers must keep this enumeration-safe (don't reveal whether the
  address exists).
  """
  def deliver_user_reset_password_instructions(%User{} = user, url_fun)
      when is_function(url_fun, 1) do
    token = generate_email_token(user, "reset_password")
    UserNotifier.deliver_reset_password_instructions(user, url_fun.(token))
  end

  @doc "User behind a valid, unexpired reset token, or nil."
  def get_user_by_reset_password_token(token) when is_binary(token) do
    get_user_by_token(token, "reset_password")
  end

  @doc """
  Sets a new password. Reaching here proves control of the email, so we
  also confirm the account (if not already) and revoke every token so
  outstanding reset/confirm links die.
  """
  def reset_user_password(%User{} = user, attrs) do
    changeset =
      user
      |> User.password_changeset(attrs)
      |> maybe_confirm()

    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, changeset)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, :user, changeset, _} -> {:error, changeset}
    end
  end

  defp maybe_confirm(changeset) do
    case changeset.data do
      %User{confirmed_at: nil} ->
        Ecto.Changeset.put_change(
          changeset,
          :confirmed_at,
          DateTime.utc_now() |> DateTime.truncate(:second)
        )

      _ ->
        changeset
    end
  end

  ## Password change (signed-in)

  @doc """
  Changes the password of a signed-in user, requiring the current
  password. `{:error, :invalid_current_password}` if it doesn't match.
  """
  def update_user_password(%User{} = user, current_password, attrs) do
    if User.valid_password?(user, current_password) do
      user
      |> User.password_changeset(attrs)
      |> Repo.update()
    else
      {:error, :invalid_current_password}
    end
  end

  ## Account disable / enable

  @doc """
  Soft-disables `user`: stamps `disabled_at`, cascades to every site the
  user owns (those sites stop resolving — 404), and revokes all tokens.
  Idempotent. Re-enable via `enable_user/1`.
  """
  def disable_user(%User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.disable_changeset(user))
    |> Ecto.Multi.run(:sites, fn _repo, _ ->
      {:ok, Sites.disable_sites_for_user(user.id)}
    end)
    |> Ecto.Multi.delete_all(:tokens, UserToken.by_user_and_contexts_query(user, :all))
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, reason}
    end
  end

  @doc """
  Re-enables a disabled account and restores its sites. Intended for
  console / admin use (there is no self-service re-enable).
  """
  def enable_user(%User{} = user) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:user, User.enable_changeset(user))
    |> Ecto.Multi.run(:sites, fn _repo, _ ->
      {:ok, Sites.enable_sites_for_user(user.id)}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{user: user}} -> {:ok, user}
      {:error, _, reason, _} -> {:error, reason}
    end
  end
end
