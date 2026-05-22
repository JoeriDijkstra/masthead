defmodule LedgerWeb.UnsubscribeHTML do
  use LedgerWeb, :html

  def onboarding(assigns) do
    ~H"""
    <div class="auth-page">
      <div class="auth-card">
        <%= if @unsubscribed do %>
          <h1>You're unsubscribed</h1>
          <p>You won't receive onboarding reminder emails from Ledger anymore.</p>
        <% else %>
          <h1>Link expired</h1>
          <p>This unsubscribe link is invalid or has expired.</p>
        <% end %>

        <p class="meta">
          <a href={~p"/"}>Back to Ledger</a>
        </p>
      </div>
    </div>
    """
  end
end
