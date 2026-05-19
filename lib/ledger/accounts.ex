defmodule Ledger.Accounts do
  alias Ledger.Repo
  alias Ledger.Accounts.User
  alias Ledger.Accounts.UserToken

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
end
