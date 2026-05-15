defmodule LedgerWeb.AdminLive.PostIndex do
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
    post = Content.get_post!(socket.assigns.site.id, id)
    {:ok, _} = Content.delete_post(post)

    {:noreply,
     socket
     |> put_flash(:info, "Post deleted.")
     |> load()}
  end

  defp load(socket) do
    posts = Content.list_posts(socket.assigns.site.id)
    assign(socket, posts: posts, page_title: "Posts — #{socket.assigns.site.name}")
  end

  defp format_label("markdown"), do: "Markdown"
  defp format_label("html"), do: "HTML"
  defp format_label(other), do: other

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Posts" site={@site} current_user={@current_user} flash={@flash} active={:posts}>
      <:actions>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary">+ New post</.link>
      </:actions>

      <table :if={@posts != []} class="table">
        <thead>
          <tr>
            <th>Title</th>
            <th>Format</th>
            <th>Status</th>
            <th>Updated</th>
            <th class="actions-cell"></th>
          </tr>
        </thead>
        <tbody>
          <tr :for={p <- @posts}>
            <td>
              <.link navigate={~p"/#{@site.slug}/posts/#{p.id}/edit"}>{p.title}</.link>
              <div class="muted">/posts/{p.slug}</div>
            </td>
            <td>
              <span class={"format-tag format-tag-" <> p.format}>{format_label(p.format)}</span>
            </td>
            <td>
              <span class={"pill pill-" <> if(p.published, do: "live", else: "draft")}>
                {if p.published, do: "Published", else: "Draft"}
              </span>
            </td>
            <td class="muted">{Calendar.strftime(p.updated_at, "%Y-%m-%d")}</td>
            <td class="actions-cell">
              <button
                type="button"
                phx-click="delete"
                phx-value-id={p.id}
                data-confirm={"Delete post \"" <> p.title <> "\"?"}
                class="btn btn-danger btn-sm"
              >
                Delete
              </button>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@posts == []} class="empty-state empty-state-illustrated">
        <img src={~p"/images/illustrations/empty-posts.svg"} alt="" class="empty-illustration" />
        <h2>No posts yet</h2>
        <p>
          Create your first post to start publishing. Drafts remain private until you publish them.
        </p>
        <.link navigate={~p"/#{@site.slug}/posts/new"} class="btn btn-primary">+ New post</.link>
      </div>
    </.shell>
    """
  end
end
