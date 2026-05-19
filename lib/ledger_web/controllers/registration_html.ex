defmodule LedgerWeb.RegistrationHTML do
  use LedgerWeb, :html

  def new(assigns) do
    ~H"""
    <div class="auth-page">
      <div class="auth-card">
        <h1>Create your Ledger account</h1>

        <form action={~p"/signup"} method="post">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <.error_list changeset={@changeset} />
          <label>
            Email
            <input
              type="email"
              name="user[email]"
              value={Ecto.Changeset.get_field(@changeset, :email) || ""}
              required
              autofocus
            />
          </label>
          <label>
            Password (min 8 chars)
            <input type="password" name="user[password]" required minlength="8" />
          </label>
          <button type="submit">Create account</button>
        </form>

        <div class="sso-divider"><span>or</span></div>
        <div class="sso-buttons">
          <a class="sso-btn" href={~p"/auth/google"}>Continue with Google</a>
          <a class="sso-btn" href={~p"/auth/github"}>Continue with GitHub</a>
        </div>

        <p class="meta">
          Already have an account? <a href={~p"/login"}>Sign in</a>
        </p>
      </div>
    </div>
    """
  end

  attr :changeset, :map, required: true

  defp error_list(assigns) do
    ~H"""
    <ul :if={@changeset.errors != []} class="errors">
      <li :for={{field, {msg, _}} <- @changeset.errors}>{field}: {msg}</li>
    </ul>
    """
  end
end
