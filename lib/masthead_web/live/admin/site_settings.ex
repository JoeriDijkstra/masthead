defmodule MastheadWeb.AdminLive.SiteSettings do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.{Actions, Sites, Content}
  alias Masthead.Content.HugoImport

  @impl true
  def mount(_params, _session, socket) do
    site = socket.assigns.site
    changeset = Sites.change_settings(site)

    {:ok,
     socket
     |> assign(
       page_title: "Settings — #{site.name}",
       published_pages: Content.list_published_pages(site.id),
       action_count: Actions.count_pending(site),
       show_errors: false,
       import_summary: nil
     )
     |> allow_upload(:site_archive,
       accept: ~w(.zip),
       max_entries: 1,
       max_file_size: 50_000_000
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
        changeset = Sites.change_settings(site)

        {:noreply,
         socket
         |> assign(
           site: site,
           published_pages: Content.list_published_pages(site.id),
           action_count: Actions.count_pending(site)
         )
         |> put_flash(:info, "Settings saved.")
         |> assign_form(changeset)}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
    end
  end

  def handle_event("validate_import", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_import", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :site_archive, ref)}
  end

  def handle_event("import_site", _params, socket) do
    site = socket.assigns.site

    [result] =
      consume_uploaded_entries(socket, :site_archive, fn %{path: path}, _entry ->
        {:ok, HugoImport.run(site, path)}
      end)

    case result do
      {:ok, summary} ->
        {:noreply,
         socket
         |> assign(
           import_summary: summary,
           published_pages: Content.list_published_pages(site.id),
           action_count: Actions.count_pending(site)
         )
         |> put_flash(:info, import_flash(summary))}

      {:error, reason} ->
        {:noreply, put_flash(socket, :error, import_error(reason))}
    end
  end

  def handle_event("delete_site", _params, socket) do
    # The site is owner-scoped by the :load_site hook, so the current user is
    # authorized. Soft-delete keeps the row recoverable (by an admin); the
    # owner can no longer reach it, so send them back to their site list.
    {:ok, _} = Sites.soft_delete_site(socket.assigns.site)

    {:noreply,
     socket
     |> put_flash(:info, "Site deleted. Contact support if you need it back.")
     |> push_navigate(to: ~p"/sites")}
  end

  defp assign_form(socket, changeset) do
    assign(socket, form: to_form(changeset, as: :site), changeset: changeset)
  end

  defp homepage_value(form), do: form[:homepage_page_id].value

  defp domain_status_label("pending_dns"), do: "awaiting DNS"
  defp domain_status_label("verified"), do: "verified"
  defp domain_status_label("cert_provisioning"), do: "issuing SSL"
  defp domain_status_label("active"), do: "active"
  defp domain_status_label("failed"), do: "needs attention"
  defp domain_status_label(other), do: other

  # Skips of section list pages (`_index.md`) are expected, not problems —
  # only surface genuinely skipped content in the summary count.
  defp problem_skips(skipped), do: Enum.reject(skipped, &(elem(&1, 1) == :section_index))

  defp import_flash(%{posts: posts, pages: pages, uploads: uploads} = summary) do
    base = "Imported #{length(posts)} posts, #{length(pages)} pages and #{uploads} assets."

    case problem_skips(summary.skipped_content) do
      [] -> base
      problems -> base <> " #{length(problems)} files couldn't be imported."
    end
  end

  defp import_error(:no_content_dir),
    do: "That archive doesn't look like a Hugo site — no content/ directory found."

  defp import_error(:too_many_files), do: "That archive has too many files."
  defp import_error(:archive_too_large), do: "That archive is too large."
  defp import_error({:archive_invalid, _}), do: "That file isn't a valid zip archive."
  defp import_error({:unzip_failed, _}), do: "Couldn't unzip that archive."
  defp import_error(_), do: "Import failed."

  defp upload_error_message(:too_large), do: "That file is too large (50MB max)."
  defp upload_error_message(:not_accepted), do: "Please choose a .zip archive."
  defp upload_error_message(:too_many_files), do: "Import one archive at a time."
  defp upload_error_message(other), do: to_string(other)

  defp problem_reason({:invalid, msg}), do: msg
  defp problem_reason(other), do: to_string(other)

  attr :summary, :map, required: true
  attr :site_slug, :string, required: true

  defp import_summary(assigns) do
    assigns = assign(assigns, :problems, problem_skips(assigns.summary.skipped_content))

    ~H"""
    <div class="import-summary">
      <p>
        <strong>Imported</strong>
        {length(@summary.posts)} posts, {length(@summary.pages)} pages and {@summary.uploads} assets.
        <span :if={@summary.skipped_assets > 0} class="muted">
          {@summary.skipped_assets} unsupported asset files were skipped.
        </span>
      </p>
      <p class="import-summary-links">
        <.link navigate={~p"/#{@site_slug}/posts"}>View posts</.link>
        <.link navigate={~p"/#{@site_slug}/pages"}>View pages</.link>
      </p>
      <details :if={@problems != []} class="import-problems">
        <summary>{length(@problems)} files couldn't be imported</summary>
        <ul>
          <li :for={{path, reason} <- @problems}>
            <code>{path}</code> — {problem_reason(reason)}
          </li>
        </ul>
      </details>
    </div>
    """
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
      action_count={@action_count}
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
              <p>Control what visitors see at the root URL.</p>
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
            </div>
          </div>

          <div class="settings-section">
            <header class="settings-section-head">
              <h2>Custom domain</h2>
              <p>Serve this site from your own domain instead of a Masthead subdomain.</p>
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
            <button type="submit" class="btn btn-primary" data-shortcut="save">
              Save settings
            </button>
          </div>
        </.form>

        <div class="settings-section">
          <header class="settings-section-head">
            <h2>Import site</h2>
            <p>
              Bring an existing Hugo site in — posts, pages, and image assets. Your theme is left untouched.
            </p>
          </header>

          <div class="settings-fields">
            <form
              id="site-import-form"
              phx-submit="import_site"
              phx-change="validate_import"
              class="form"
            >
              <label class="dropzone" phx-drop-target={@uploads.site_archive.ref}>
                <.live_file_input upload={@uploads.site_archive} />
                <p class="dropzone-headline">Drop a Hugo site .zip here, or click to browse</p>
                <p class="muted">
                  <code>content/</code> becomes posts and pages, <code>static/</code> images
                  become uploads. Frontmatter titles and <code>draft</code> state are honoured
                  and asset URLs are rewritten. Up to 50MB.
                </p>
              </label>

              <ul :if={@uploads.site_archive.entries != []} class="upload-entries">
                <li :for={entry <- @uploads.site_archive.entries}>
                  <span class="filename">{entry.client_name}</span>
                  <button
                    type="button"
                    phx-click="cancel_import"
                    phx-value-ref={entry.ref}
                    class="btn btn-sm"
                  >
                    Remove
                  </button>
                  <p
                    :for={err <- upload_errors(@uploads.site_archive, entry)}
                    class="error entry-error"
                  >
                    {upload_error_message(err)}
                  </p>
                </li>
              </ul>

              <p :for={err <- upload_errors(@uploads.site_archive)} class="error">
                {upload_error_message(err)}
              </p>

              <.import_summary
                :if={@import_summary}
                summary={@import_summary}
                site_slug={@site.slug}
              />

              <div class="wizard-footer">
                <button
                  type="submit"
                  class="btn btn-primary"
                  disabled={@uploads.site_archive.entries == []}
                >
                  Import site
                </button>
              </div>
            </form>
          </div>
        </div>

        <div class="settings-section danger-zone">
          <header class="settings-section-head">
            <h2>Danger zone</h2>
            <p>Permanently remove this site from your account.</p>
          </header>
          <div class="danger-row">
            <div>
              <strong>Delete this site</strong>
              <p class="muted">
                Takes <code>{@site.slug}</code> offline and removes it from your sites.
                The data is retained for recovery — contact support if you delete it by mistake.
              </p>
            </div>
            <button
              type="button"
              phx-click="delete_site"
              class="btn btn-danger"
              data-confirm={"Delete #{@site.name}? It will go offline immediately and disappear from your sites."}
            >
              Delete site
            </button>
          </div>
        </div>
      </div>
    </.shell>
    """
  end
end
