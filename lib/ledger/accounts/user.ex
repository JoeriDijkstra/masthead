defmodule Ledger.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :password, :string, virtual: true, redact: true
    field :hashed_password, :string, redact: true
    field :confirmed_at, :utc_datetime
    field :disabled_at, :utc_datetime

    has_many :tokens, Ledger.Accounts.UserToken

    timestamps(type: :utc_datetime)
  end

  @doc "Email is confirmed."
  def confirmed?(%__MODULE__{confirmed_at: at}), do: not is_nil(at)

  @doc "Account is disabled (self-serve or auto-disabled)."
  def disabled?(%__MODULE__{disabled_at: at}), do: not is_nil(at)

  @doc "Marks the email confirmed (no-op effect if already confirmed)."
  def confirm_changeset(user) do
    change(user, confirmed_at: now())
  end

  @doc "Soft-disables the account."
  def disable_changeset(user) do
    change(user, disabled_at: now())
  end

  @doc "Clears the disabled flag (re-enable)."
  def enable_changeset(user) do
    change(user, disabled_at: nil)
  end

  @doc "Sets a new password (password-reset flow)."
  def password_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> hash_password()
  end

  @doc """
  Registers a user that authenticated via OAuth. The email is owned by
  the provider (and we only reach here for verified emails), so the
  account starts confirmed. A random password is set so password login
  is effectively disabled until the user resets it.
  """
  def oauth_registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email])
    |> validate_required([:email])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:email, max: 160)
    |> unsafe_validate_unique(:email, Ledger.Repo)
    |> unique_constraint(:email)
    |> put_change(:password, random_password())
    |> put_change(:confirmed_at, now())
    |> hash_password()
  end

  defp random_password, do: :crypto.strong_rand_bytes(24) |> Base.url_encode64()

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> validate_required([:email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:email, max: 160)
    |> validate_length(:password, min: 8, max: 72)
    |> unsafe_validate_unique(:email, Ledger.Repo)
    |> unique_constraint(:email)
    |> hash_password()
  end

  defp hash_password(changeset) do
    case get_change(changeset, :password) do
      nil ->
        changeset

      pw ->
        changeset
        |> put_change(:hashed_password, Bcrypt.hash_pwd_salt(pw))
        |> delete_change(:password)
    end
  end

  def valid_password?(%__MODULE__{hashed_password: hash}, password)
      when is_binary(hash) and byte_size(password) > 0 do
    Bcrypt.verify_pass(password, hash)
  end

  def valid_password?(_, _) do
    Bcrypt.no_user_verify()
    false
  end
end
