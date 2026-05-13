defmodule LedgerWeb.AdminLive.SiteSettings do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.{Sites, Themes, Content}

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site
    changeset = Sites.change_settings(site)

    {:ok,
     socket
     |> assign(
       page_title: "Settings — #{site.name}",
       themes: Themes.names(),
       published_pages: Content.list_published_pages(site.id)
     )
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    changeset =
      socket.assigns.site
      |> Sites.change_settings(params)
      |> Map.put(:action, :validate)

    {:noreply, assign_form(socket, changeset)}
  end

  def handle_event("save", %{"site" => params}, socket) do
    case Sites.update_settings(socket.assigns.site, params) do
      {:ok, site} ->
        {:noreply,
         socket
         |> assign(
           site: site,
           published_pages: Content.list_published_pages(site.id)
         )
         |> put_flash(:info, "Settings saved.")
         |> assign_form(Sites.change_settings(site))}

      {:error, changeset} ->
        {:noreply, assign_form(socket, changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :site), changeset: changeset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Settings" site={@site} current_user={@current_user} flash={@flash}>
      <.form for={@form} phx-change="validate" phx-submit="save" class="form">
        <.error_list changeset={@changeset} />

        <label>
          Name
          <input type="text" name="site[name]" value={@form[:name].value} required />
        </label>

        <label>
          Title
          <input type="text" name="site[title]" value={@form[:title].value} />
        </label>

        <label>
          Description
          <textarea name="site[description]" rows="3">{@form[:description].value}</textarea>
        </label>

        <label>
          Homepage
          <select name="site[homepage_page_id]">
            <option value="" selected={is_nil(homepage_value(@form))}>Default — list of posts</option>
            <option
              :for={page <- @published_pages}
              value={page.id}
              selected={to_string(page.id) == to_string(homepage_value(@form))}>
              {page.title} ({page.format})
            </option>
          </select>
          <small>What visitors see at the site root. Pick a page to override the default post list.</small>
        </label>

        <label>
          Theme
          <select name="site[theme]">
            <option :for={t <- @themes} value={t} selected={t == @form[:theme].value}>{t}</option>
          </select>
        </label>

        <p class="muted">Slug: <code>{@site.slug}</code> (cannot be changed in MVP)</p>

        <div class="form-actions">
          <button type="submit" class="btn btn-primary">Save settings</button>
          <.link navigate={~p"/admin/sites/#{@site.id}"}>Back</.link>
        </div>
      </.form>
    </.shell>
    """
  end

  defp homepage_value(form), do: form[:homepage_page_id].value
end
