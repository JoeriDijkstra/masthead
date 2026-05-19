defmodule LedgerWeb.SSO do
  @moduledoc """
  Renders the social sign-in buttons, showing a provider only when its
  OAuth client is actually configured (client id present in the env).
  Used by the sign-in and sign-up pages.
  """
  use Phoenix.Component
  use LedgerWeb, :verified_routes

  @providers [
    {:google, "Continue with Google", Ueberauth.Strategy.Google.OAuth},
    {:github, "Continue with GitHub", Ueberauth.Strategy.Github.OAuth}
  ]

  @doc "Configured providers as `[%{id: atom, label: string}]`."
  def configured do
    for {id, label, oauth_mod} <- @providers,
        configured?(oauth_mod),
        do: %{id: id, label: label}
  end

  defp configured?(oauth_mod) do
    case Application.get_env(:ueberauth, oauth_mod) do
      nil -> false
      cfg -> cfg[:client_id] not in [nil, ""]
    end
  end

  @doc "Divider + one button per configured provider. Nothing if none."
  def buttons(assigns) do
    assigns = assign(assigns, :providers, configured())

    ~H"""
    <div :if={@providers != []}>
      <div class="sso-divider"><span>or</span></div>
      <div class="sso-buttons">
        <a :for={p <- @providers} class="sso-btn" href={~p"/auth/#{p.id}"}>{p.label}</a>
      </div>
    </div>
    """
  end
end
