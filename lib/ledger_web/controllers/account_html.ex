defmodule LedgerWeb.AccountHTML do
  use LedgerWeb, :html

  alias Ledger.Accounts.User

  attr :user, :map, required: true
  attr :password_changeset, :map, required: true

  def show(assigns) do
    ~H"""
    <div class="auth-page">
      <div class="auth-card">
        <h1>Account</h1>

        <p :if={Phoenix.Flash.get(@flash, :error)} class="error">
          {Phoenix.Flash.get(@flash, :error)}
        </p>
        <p :if={Phoenix.Flash.get(@flash, :info)} class="meta">
          {Phoenix.Flash.get(@flash, :info)}
        </p>

        <section>
          <h2>Email</h2>
          <p class="meta">{@user.email}</p>
          <%= if User.confirmed?(@user) do %>
            <p class="meta">✓ Confirmed</p>
          <% else %>
            <p class="meta">Not confirmed yet.</p>
            <form action={~p"/confirm"} method="post">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit">Resend confirmation email</button>
            </form>
          <% end %>
        </section>

        <section>
          <h2>Change password</h2>
          <form action={~p"/account/password"} method="post">
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <.error_list changeset={@password_changeset} />
            <label>
              Current password <input type="password" name="current_password" required />
            </label>
            <label>
              New password (min 8 chars)
              <input type="password" name="user[password]" required minlength="8" />
            </label>
            <button type="submit">Update password</button>
          </form>
        </section>

        <section class="danger-zone">
          <h2>Disable account</h2>
          <p class="meta">
            This disables your account and takes all of your sites offline immediately.
            You won't be able to sign back in. This cannot be undone from here.
          </p>
          <form
            action={~p"/account/disable"}
            method="post"
            onsubmit="return confirm('Disable your account and take all your sites offline? You will be logged out and cannot undo this yourself.');"
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button type="submit" class="danger">Disable my account</button>
          </form>
        </section>

        <p class="meta"><a href={~p"/sites"}>Back to your sites</a></p>
      </div>
    </div>
    """
  end

  attr :changeset, :map, required: true

  defp error_list(assigns) do
    ~H"""
    <ul :if={@changeset.errors != []} class="errors">
      <li :for={{field, {msg, opts}} <- @changeset.errors}>{field}: {interpolate(msg, opts)}</li>
    </ul>
    """
  end

  defp interpolate(msg, opts) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end
