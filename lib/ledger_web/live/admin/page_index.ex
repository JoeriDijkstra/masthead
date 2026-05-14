defmodule LedgerWeb.AdminLive.PageIndex do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.Content

  @impl true
  def mount(_params, _session, socket) do
    {:ok, load(socket)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    page = Content.get_page!(socket.assigns.site.id, id)
    {:ok, _} = Content.delete_page(page)

    {:noreply,
     socket
     |> put_flash(:info, "Page deleted.")
     |> load()}
  end

  defp load(socket) do
    pages = Content.list_pages(socket.assigns.site.id)
    assign(socket, pages: pages, page_title: "Pages — #{socket.assigns.site.name}")
  end

  defp format_label("markdown"), do: "Markdown"
  defp format_label("html"), do: "HTML"
  defp format_label("blog"), do: "Blog"
  defp format_label(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Pages" site={@site} current_user={@current_user} flash={@flash} active={:pages}>
      <:actions>
        <.link navigate={~p"/#{@site.slug}/pages/new"} class="btn btn-primary">+ New page</.link>
      </:actions>

      <table :if={@pages != []} class="table">
        <thead>
          <tr><th>Title</th><th>Format</th><th>Status</th><th class="actions-cell"></th></tr>
        </thead>
        <tbody>
          <tr :for={p <- @pages}>
            <td>
              <.link navigate={~p"/#{@site.slug}/pages/#{p.id}/edit"}>{p.title}</.link>
              <div class="muted">/{p.slug}</div>
            </td>
            <td>
              <span class={"format-tag format-tag-" <> p.format}>{format_label(p.format)}</span>
            </td>
            <td>
              <span class={"pill pill-" <> if(p.published, do: "live", else: "draft")}>{if p.published, do: "Published", else: "Draft"}</span>
            </td>
            <td class="actions-cell">
              <button type="button" phx-click="delete" phx-value-id={p.id} data-confirm={"Delete page \"" <> p.title <> "\"?"} class="btn btn-danger btn-sm">Delete</button>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@pages == []} class="empty-state empty-state-illustrated">
        <img src={~p"/images/illustrations/empty-pages.svg"} alt="" class="empty-illustration" />
        <h2>No pages yet</h2>
        <p>Pages are standalone content such as About or Contact. Published pages appear in the site navigation.</p>
        <.link navigate={~p"/#{@site.slug}/pages/new"} class="btn btn-primary">+ New page</.link>
      </div>
    </.shell>
    """
  end
end
