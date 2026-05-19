defmodule LedgerWeb.AccountHTML do
  use LedgerWeb, :html

  alias Ledger.Accounts.User
  alias LedgerWeb.AdminLive.Components

  attr :user, :map, required: true
  attr :password_changeset, :map, required: true

  def show(assigns) do
    ~H"""
    <Components.shell title="Account" current_user={@user} flash={@flash}>
      <div class="settings-section">
        <header class="settings-section-head">
          <h2>Email</h2>
          <p>The address you sign in with and where account email is sent.</p>
        </header>
        <div class="settings-fields">
          <p class="account-email">{@user.email}</p>
          <%= if User.confirmed?(@user) do %>
            <p class="meta">✓ Confirmed</p>
          <% else %>
            <p class="meta">Not confirmed yet.</p>
            <form action={~p"/confirm"} method="post">
              <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
              <button type="submit" class="btn">Resend confirmation email</button>
            </form>
          <% end %>
        </div>
      </div>

      <div class="settings-section">
        <header class="settings-section-head">
          <h2>Password</h2>
          <p>Used for email / password sign-in.</p>
        </header>
        <div class="settings-fields">
          <button
            type="button"
            class="btn"
            onclick="document.getElementById('pw-modal').showModal()"
          >
            Change password…
          </button>
        </div>
      </div>

      <div class="settings-section danger-zone">
        <header class="settings-section-head">
          <h2>Disable account</h2>
          <p>
            Disables your account and takes all of your sites offline immediately.
            You won't be able to sign back in, and this can't be undone here.
          </p>
        </header>
        <div class="settings-fields">
          <form
            action={~p"/account/disable"}
            method="post"
            onsubmit="return confirm('Disable your account and take all your sites offline? You will be logged out and cannot undo this yourself.');"
          >
            <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
            <button type="submit" class="btn btn-danger">Disable my account</button>
          </form>
        </div>
      </div>

      <dialog
        id="pw-modal"
        class="modal"
        open={@password_changeset.action != nil}
      >
        <form action={~p"/account/password"} method="post" class="modal-card">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <h2>Change password</h2>
          <.error_list changeset={@password_changeset} />
          <label>
            Current password <input type="password" name="current_password" required />
          </label>
          <label>
            New password (min 8 chars)
            <input type="password" name="user[password]" required minlength="8" />
          </label>
          <div class="modal-actions">
            <button
              type="button"
              class="btn"
              onclick="document.getElementById('pw-modal').close()"
            >
              Cancel
            </button>
            <button type="submit" class="btn btn-primary">Update password</button>
          </div>
        </form>
      </dialog>
    </Components.shell>
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
