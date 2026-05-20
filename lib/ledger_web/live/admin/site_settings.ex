defmodule LedgerWeb.AdminLive.SiteSettings do
  use LedgerWeb, :live_view
  on_mount {LedgerWeb.AdminLive.Hooks, :load_site}

  import LedgerWeb.AdminLive.Components
  alias Ledger.{Sites, Themes, Content}

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site
    changeset = Sites.change_settings(site)
    themes = Themes.list_themes(socket.assigns.current_user.id)

    {:ok,
     socket
     |> assign(
       page_title: "Settings — #{site.name}",
       themes: themes,
       published_pages: Content.list_published_pages(site.id),
       show_errors: false,
       selected_theme: pick_theme(themes, current_theme_id(changeset, site))
     )
     |> assign_form(changeset)}
  end

  @impl true
  def handle_event("validate", %{"site" => params}, socket) do
    changeset =
      socket.assigns.site
      |> Sites.change_settings(params)
      |> Map.put(:action, :validate)

    selected = pick_theme(socket.assigns.themes, current_theme_id(changeset, socket.assigns.site))

    {:noreply, socket |> assign(selected_theme: selected) |> assign_form(changeset)}
  end

  def handle_event("save", %{"site" => params}, socket) do
    case Sites.update_settings(socket.assigns.site, params) do
      {:ok, site} ->
        Ledger.Themes.Loader.invalidate(site.theme_id)
        changeset = Sites.change_settings(site)

        {:noreply,
         socket
         |> assign(
           site: site,
           published_pages: Content.list_published_pages(site.id),
           selected_theme: pick_theme(socket.assigns.themes, site.theme_id)
         )
         |> put_flash(:info, "Settings saved.")
         |> assign_form(changeset)}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :site), changeset: changeset)
  end

  defp current_theme_id(changeset, site) do
    case Ecto.Changeset.get_field(changeset, :theme_id) do
      nil -> site.theme_id
      id -> id
    end
  end

  defp pick_theme(themes, nil), do: List.first(themes)

  defp pick_theme(themes, id) do
    Enum.find(themes, List.first(themes), fn t -> t.id == id end)
  end

  defp homepage_value(form), do: form[:homepage_page_id].value

  # Manifest tokens are stored on the row as a plain map. Pull out the
  # token definitions (key/label/type/default) so the template can render
  # an input per token.
  defp token_definitions(nil), do: []

  defp token_definitions(%Ledger.Themes.Theme{manifest: %{} = m}) do
    case Map.get(m, "tokens", Map.get(m, :tokens, [])) do
      list when is_list(list) ->
        Enum.map(list, fn t ->
          %{
            key: t["key"] || t[:key],
            label: t["label"] || t[:label],
            type: t["type"] || t[:type],
            default: t["default"] || t[:default]
          }
        end)

      _ ->
        []
    end
  end

  defp token_value(form, key) do
    case form[:theme_tokens].value do
      %{} = m -> Map.get(m, key) || Map.get(m, to_string(key)) || ""
      _ -> ""
    end
  end

  defp html_input_type("color"), do: "color"
  defp html_input_type("number"), do: "number"
  defp html_input_type(_), do: "text"

  defp domain_status_label("pending_dns"), do: "awaiting DNS"
  defp domain_status_label("verified"), do: "verified"
  defp domain_status_label("cert_provisioning"), do: "issuing SSL"
  defp domain_status_label("active"), do: "active"
  defp domain_status_label("failed"), do: "needs attention"
  defp domain_status_label(other), do: other

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
        <.form
          for={@form}
          phx-change="validate"
          phx-submit="save"
          class="form settings-form"
          id="site-settings-form"
        >
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
                  class={"theme-picker-card" <> if(@selected_theme && t.id == @selected_theme.id, do: " theme-picker-card-selected", else: "")}
                >
                  <input
                    type="radio"
                    name="site[theme_id]"
                    value={t.id}
                    checked={@selected_theme && t.id == @selected_theme.id}
                  />
                  <span class="theme-picker-card-name">
                    {t.name}<span :if={t.source == "uploaded"} class="theme-picker-card-tag">uploaded</span>
                  </span>
                </label>
                <a
                  href="https://github.com/JoeriDijkstra/ledger-template"
                  target="_blank"
                  rel="noopener"
                  class="theme-picker-card theme-picker-card-add"
                >
                  <span class="theme-picker-card-icon" aria-hidden="true">+</span>
                  <span class="theme-picker-card-name">Add a custom theme</span>
                </a>
                <small class="theme-picker-hint">
                  Rendering style applied to the public site.
                </small>
              </fieldset>
            </div>
          </div>

          <div
            :if={@selected_theme && token_definitions(@selected_theme) != []}
            class="settings-section"
          >
            <header class="settings-section-head">
              <h2>Theme customization</h2>
              <p>Override the {@selected_theme.name} theme's design tokens.</p>
            </header>

            <div class="settings-fields">
              <label :for={tok <- token_definitions(@selected_theme)}>
                {tok.label}
                <input
                  type={html_input_type(tok.type)}
                  name={"site[theme_tokens][" <> tok.key <> "]"}
                  value={token_value(@form, tok.key)}
                  placeholder={tok.default}
                />
                <small>Default: <code>{tok.default}</code></small>
              </label>
            </div>
          </div>

          <div :if={@selected_theme} class="settings-section">
            <header class="settings-section-head">
              <h2>Custom CSS</h2>
              <p>Optional escape hatch — appended after the theme's stylesheet.</p>
            </header>

            <div class="settings-fields">
              <label>
                CSS overrides <textarea
                  name="site[theme_css_overrides]"
                  rows="6"
                  placeholder=".my-class { color: red; }"
                >{@form[:theme_css_overrides].value}</textarea>
                <small>Up to 50 KB. No imports or external resources.</small>
              </label>
            </div>
          </div>

          <div class="settings-section">
            <header class="settings-section-head">
              <h2>Custom domain</h2>
              <p>Serve this site from your own domain instead of a Ledger subdomain.</p>
            </header>

            <div class="settings-fields">
              <div :if={@site.custom_domain} class="domain-summary">
                <span>
                  <strong>{@site.custom_domain}</strong>
                  <span class={"domain-badge domain-badge-" <> @site.custom_domain_status}>
                    {domain_status_label(@site.custom_domain_status)}
                  </span>
                </span>
                <.link navigate={~p"/#{@site.slug}/domain"} class="btn">Manage</.link>
              </div>

              <div :if={is_nil(@site.custom_domain)} class="domain-summary">
                <span class="muted">No custom domain configured.</span>
                <.link navigate={~p"/#{@site.slug}/domain"} class="btn btn-primary">
                  Set up a custom domain
                </.link>
              </div>
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
end
