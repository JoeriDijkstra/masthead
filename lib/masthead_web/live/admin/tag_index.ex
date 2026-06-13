defmodule MastheadWeb.AdminLive.TagIndex do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.Content

  @impl true
  def mount(_params, _session, socket), do: {:ok, load(socket)}

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    tag = Content.get_tag!(socket.assigns.site.id, id)
    {:ok, _} = Content.delete_tag(tag)

    {:noreply,
     socket
     |> put_flash(:info, "Tag deleted.")
     |> load()}
  end

  defp load(socket) do
    tags = Content.list_tags(socket.assigns.site.id)
    assign(socket, tags: tags, page_title: "Tags — #{socket.assigns.site.name}")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Tags" site={@site} current_user={@current_user} flash={@flash} active={:tags}>
      <:actions>
        <.link
          navigate={~p"/#{@site.slug}/tags/new"}
          class="btn btn-primary btn-add"
          data-shortcut="new"
        >
          <span class="btn-add-icon" aria-hidden="true">+</span>
          <span class="btn-add-label">New tag</span>
        </.link>
      </:actions>

      <table :if={@tags != []} class="table table-cards">
        <thead>
          <tr>
            <th>Name</th>
            <th>Slug</th>
            <th>Created</th>
            <th class="actions-cell"></th>
          </tr>
        </thead>
        <tbody>
          <tr
            :for={t <- @tags}
            class="row-link"
            phx-click={JS.navigate(~p"/#{@site.slug}/tags/#{t.id}/edit")}
          >
            <td>
              <span class="tag-chip" style={tag_chip_style(t)}>{t.name}</span>
            </td>
            <td data-label="Slug"><span class="muted">{t.slug}</span></td>
            <td data-label="Created"><.relative_time at={t.inserted_at} /></td>
            <td class="actions-cell">
              <div class="row-actions">
                <button
                  type="button"
                  phx-click={JS.navigate(~p"/#{@site.slug}/tags/#{t.id}/edit")}
                  class="btn btn-sm"
                >
                  Edit
                </button>
                <button
                  type="button"
                  phx-click="delete"
                  phx-value-id={t.id}
                  data-confirm={"Delete tag \"" <> t.name <> "\"? Posts keep their other tags."}
                  class="btn btn-danger btn-sm"
                >
                  Delete
                </button>
              </div>
            </td>
          </tr>
        </tbody>
      </table>

      <div :if={@tags == []} class="empty-state">
        <h2>No tags yet</h2>
        <p>
          Tags group posts together. Create a tag, assign it to posts, then filter your
          posts by it here — or query it from your theme with <code>posts | where_tag: "your-tag"</code>.
        </p>
        <.link navigate={~p"/#{@site.slug}/tags/new"} class="btn btn-primary">+ New tag</.link>
      </div>
    </.shell>
    """
  end

  defp tag_chip_style(%{color: color}) when is_binary(color),
    do: "--tag-color: #{color}; background: #{color}; color: #fff;"

  defp tag_chip_style(_), do: nil
end
