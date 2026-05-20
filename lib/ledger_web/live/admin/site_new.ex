defmodule LedgerWeb.AdminLive.SiteNew do
  use LedgerWeb, :live_view
  import LedgerWeb.AdminLive.Components
  alias Ledger.Sites
  alias Ledger.Sites.Site

  @impl true
  def mount(_params, _session, socket) do
    changeset = Sites.change_site(%Site{})

    {:ok,
     socket
     |> assign(page_title: "New site", host_example: host_example(), show_errors: false)
     |> assign_form(changeset)}
  end

  defp host_example do
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

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    changeset =
      %Site{}
      |> Sites.change_site(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"site" => params}, socket) do
    params = Map.put(params, "owner_id", socket.assigns.current_user.id)

    case Sites.create_site(params) do
      {:ok, site} ->
        {:noreply,
         socket
         |> put_flash(:info, "Site #{site.name} created.")
         |> push_navigate(to: ~p"/#{site.slug}")}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :site), changeset: changeset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Create a new site" current_user={@current_user} flash={@flash} active={:new_site}>
      <.form for={@form} phx-change="validate" phx-submit="save" class="form">
        <.error_list changeset={@changeset} show={@show_errors} />

        <label>
          Name <input type="text" name="site[name]" value={@form[:name].value} required autofocus />
          <small>Shown in nav and as default page title.</small>
        </label>

        <label>
          Slug (subdomain) <input type="text" name="site[slug]" value={@form[:slug].value} required />
          <small>
            Used to build the site's public URL: <code>{(@form[:slug].value || "your-slug") <> "." <> @host_example}</code>.
            Lowercase letters, numbers, and hyphens only.
          </small>
        </label>

        <label>
          Title <input type="text" name="site[title]" value={@form[:title].value} />
        </label>

        <label>
          Description <textarea name="site[description]" rows="3">{@form[:description].value}</textarea>
        </label>

        <div class="form-actions">
          <button type="submit" class="btn btn-primary">Create site</button>
          <.link navigate={~p"/sites"}>Cancel</.link>
        </div>
      </.form>
    </.shell>
    """
  end
end
