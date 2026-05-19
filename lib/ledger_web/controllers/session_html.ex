defmodule LedgerWeb.SessionHTML do
  use LedgerWeb, :html

  def new(assigns) do
    ~H"""
    <div class="auth-page">
      <div class="auth-card">
        <h1>Sign in to Ledger</h1>
        <p :if={@error} class="error">{@error}</p>

        <form action={~p"/login"} method="post">
          <input type="hidden" name="_csrf_token" value={Phoenix.Controller.get_csrf_token()} />
          <label>
            Email <input type="email" name="user[email]" value={@email} required autofocus />
          </label>
          <label>
            Password <input type="password" name="user[password]" required />
          </label>
          <button type="submit">Sign in</button>
        </form>

        <LedgerWeb.SSO.buttons />

        <p class="meta">
          Need an account? <a href={~p"/signup"}>Sign up</a>
        </p>
        <p class="meta">
          <a href={~p"/reset-password"}>Forgot your password?</a>
        </p>
      </div>
    </div>
    """
  end
end
