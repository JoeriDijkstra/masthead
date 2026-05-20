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
       published_pages: Content.list_published_pages(site.id),
       show_errors: false
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
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :site), changeset: changeset)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell
      title="Settings"
      site={@site}
      current_user={@current_user}
      flash={@flash}
      active={:settings}
    >
      <div class="wizard">
        <.form for={@form} phx-change="validate" phx-submit="save" class="form settings-form">
          <.error_list changeset={@changeset} show={@show_errors} />

          <div class="settings-section">
            <header class="settings-section-head">
              <h2>Identity</h2>
              <p>Name and presentation shown across the public site.</p>
            </header>

            <div class="settings-fields">
              <div class="form-row">
                <label class="flex-1">
                  Name <input type="text" name="site[name]" value={@form[:name].value} required />
                </label>

                <label class="flex-1">
                  Title <input type="text" name="site[title]" value={@form[:title].value} />
                  <small>Used in the browser tab and as the homepage heading.</small>
                </label>
              </div>

              <label>
                Description <textarea name="site[description]" rows="3">{@form[:description].value}</textarea>
                <small>Shown on the default homepage and in the &lt;meta&gt; description.</small>
              </label>
            </div>
          </div>

          <div class="settings-section">
            <header class="settings-section-head">
              <h2>Public site</h2>
              <p>Control what visitors see at the root URL and how the site is styled.</p>
            </header>

            <div class="settings-fields">
              <label>
                Homepage
                <select name="site[homepage_page_id]">
                  <option value="" selected={is_nil(homepage_value(@form))}>
                    Default — list of posts
                  </option>
                  <option
                    :for={page <- @published_pages}
                    value={page.id}
                    selected={to_string(page.id) == to_string(homepage_value(@form))}
                  >
                    {page.title} ({page.format})
                  </option>
                </select>
                <small>Pick a page to override the default post list.</small>
              </label>

              <fieldset class="theme-picker">
                <legend>Theme</legend>
                <label
                  :for={t <- @themes}
                  class={"theme-card" <> if(t == @form[:theme].value, do: " theme-card-selected", else: "")}
                >
                  <input
                    type="radio"
                    name="site[theme]"
                    value={t}
                    checked={t == @form[:theme].value}
                  />
                  <span class="theme-card-name">{String.capitalize(t)}</span>
                </label>
                <a
                  href="https://github.com/JoeriDijkstra/ledger-template"
                  target="_blank"
                  rel="noopener"
                  class="theme-card theme-card-add"
                >
                  <span class="theme-card-icon" aria-hidden="true">+</span>
                  <span class="theme-card-name">Add a custom theme</span>
                </a>
                <small class="theme-picker-hint">
                  Rendering style applied to the public site.
                </small>
              </fieldset>
            </div>
          </div>

          <div class="wizard-footer">
            <.link navigate={~p"/#{@site.slug}"} class="btn">Cancel</.link>
            <button type="submit" class="btn btn-primary">Save settings</button>
          </div>
        </.form>
      </div>
    </.shell>
    """
  end

  defp homepage_value(form), do: form[:homepage_page_id].value
end
