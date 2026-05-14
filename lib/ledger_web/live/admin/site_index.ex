defmodule LedgerWeb.AdminLive.SiteIndex do
  use LedgerWeb, :live_view
  import LedgerWeb.AdminLive.Components
  alias Ledger.Sites

  @impl true
  def mount(_params, _session, socket) do
    sites = Sites.list_sites_for_user(socket.assigns.current_user.id)
    {:ok, assign(socket, sites: sites, page_title: "Your sites")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Your sites" current_user={@current_user} flash={@flash} active={:sites}>
      <:actions>
        <.link navigate={~p"/sites/new"} class="btn btn-primary">+ New site</.link>
      </:actions>

      <ul :if={@sites != []} class="card-list">
        <li :for={s <- @sites}>
          <.link navigate={~p"/#{s.slug}"}>
            <strong>{s.name}</strong>
            <span class="muted">{s.slug}.lvh.me</span>
          </.link>
        </li>
      </ul>

      <p :if={@sites == []} class="empty">
        You don't have any sites yet.
        <.link navigate={~p"/sites/new"}>Create your first site</.link>.
      </p>
    </.shell>
    """
  end
end
