defmodule LedgerWeb.AdminLive.SiteIndex do
  use LedgerWeb, :live_view
  import LedgerWeb.AdminLive.Components
  alias Ledger.Sites

  @impl true
  def mount(_params, _session, socket) do
    sites = Sites.list_sites_for_user(socket.assigns.current_user.id)
    {:ok, assign(socket, sites: sites, page_title: "Your sites", host: site_host())}
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
            <span class="muted">{s.slug}.{@host}</span>
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

  defp site_host do
    cfg = Application.get_env(:ledger, :site_url, [])
    host = Keyword.get(cfg, :host, "lvh.me")
    port = Keyword.get(cfg, :port)
    scheme = Keyword.get(cfg, :scheme, "http")

    suffix =
      cond do
        is_nil(port) -> ""
        scheme == "http" and port == 80 -> ""
        scheme == "https" and port == 443 -> ""
        true -> ":#{port}"
      end

    "#{host}#{suffix}"
  end
end
