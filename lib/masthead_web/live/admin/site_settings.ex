defmodule MastheadWeb.AdminLive.SiteSettings do
  use MastheadWeb, :live_view
  on_mount {MastheadWeb.AdminLive.Hooks, :load_site}

  import MastheadWeb.AdminLive.Components
  alias Masthead.{Actions, Sites, Themes, Content, Uploads}

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
       site_uploads: Uploads.list_uploads(site.id),
       action_count: Actions.count_pending(site),
       show_errors: false,
       picker_open?: false,
       picker_view: :grid,
       picker_token: nil,
       open_token_group: nil,
       selected_theme: pick_theme(themes, current_theme_id(changeset, site))
     )
     |> allow_upload(:picker_image,
       accept: ~w(.png .jpg .jpeg .gif .webp .svg .ico .pdf),
       max_entries: 1,
       max_file_size: 8_000_000
     )
     |> assign_form(changeset)}
  end

  @impl true
  # Track the single open token-category accordion server-side, so a form
  # re-render (phx-change while typing) doesn't reset the native `<details>`
  # state. Only one category is open at a time; clicking the open one closes it.
  def handle_event("toggle_token_group", %{"group" => group}, socket) do
    open = if socket.assigns.open_token_group == group, do: nil, else: group
    {:noreply, assign(socket, open_token_group: open)}
  end

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
        Masthead.Themes.Loader.invalidate(site.theme_id)
        changeset = Sites.change_settings(site)

        {:noreply,
         socket
         |> assign(
           site: site,
           published_pages: Content.list_published_pages(site.id),
           action_count: Actions.count_pending(site),
           selected_theme: pick_theme(socket.assigns.themes, site.theme_id)
         )
         |> put_flash(:info, "Settings saved.")
         |> assign_form(changeset)}

      {:error, changeset} ->
        {:noreply, socket |> assign(show_errors: true) |> assign_form(changeset)}
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

  # ---- file-token picker modal ----

  def handle_event("open_picker", %{"token" => key}, socket) do
    {:noreply, assign(socket, picker_open?: true, picker_view: :grid, picker_token: key)}
  end

  def handle_event("open_uploader", _params, socket) do
    {:noreply, assign(socket, picker_view: :upload)}
  end

  def handle_event("back_to_grid", _params, socket) do
    {:noreply, socket |> cancel_picker_uploads() |> assign(picker_view: :grid)}
  end

  def handle_event("close_picker", _params, socket) do
    {:noreply, socket |> cancel_picker_uploads() |> close_picker()}
  end

  def handle_event("select_upload", %{"id" => id}, socket) do
    changeset = set_token(socket, socket.assigns.picker_token, id)

    {:noreply,
     socket
     |> cancel_picker_uploads()
     |> close_picker()
     |> assign_form(changeset)}
  end

  def handle_event("clear_token", %{"token" => key}, socket) do
    {:noreply, assign_form(socket, set_token(socket, key, ""))}
  end

  def handle_event("validate_picker", _params, socket), do: {:noreply, socket}

  def handle_event("cancel_picker_entry", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :picker_image, ref)}
  end

  def handle_event("upload_file", _params, socket) do
    results =
      consume_uploaded_entries(socket, :picker_image, fn %{path: path}, entry ->
        attrs = %{
          filename: entry.client_name,
          content_type: entry.client_type,
          path: path
        }

        case Uploads.store_image(socket.assigns.site, attrs) do
          {:ok, upload} -> {:ok, upload}
          {:error, reason} -> {:postpone, reason}
        end
      end)

    socket = assign(socket, site_uploads: Uploads.list_uploads(socket.assigns.site.id))

    case results do
      [%Masthead.Uploads.Upload{} = upload | _] ->
        # Newly uploaded file is immediately selected for the active token.
        changeset = set_token(socket, socket.assigns.picker_token, to_string(upload.id))

        {:noreply,
         socket
         |> close_picker()
         |> put_flash(:info, "Uploaded #{upload.filename}.")
         |> assign_form(changeset)}

      _ ->
        {:noreply, socket}
    end
  end

  defp close_picker(socket) do
    assign(socket, picker_open?: false, picker_view: :grid, picker_token: nil)
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

  defp token_definitions(%Masthead.Themes.Theme{manifest: %{} = m}) do
    case Map.get(m, "tokens", Map.get(m, :tokens, [])) do
      list when is_list(list) ->
        Enum.map(list, fn t ->
          %{
            key: t["key"] || t[:key],
            label: t["label"] || t[:label],
            type: t["type"] || t[:type],
            default: t["default"] || t[:default],
            options: t["options"] || t[:options] || [],
            category: t["category"] || t[:category]
          }
        end)

      _ ->
        []
    end
  end

  # Decide how to lay out the token fields:
  #   * `{:flat, tokens}`    — no token declares a category; render as a
  #     single list (unchanged behaviour).
  #   * `{:grouped, groups}` — at least one token has a category; render one
  #     accordion per category, in first-appearance order, with uncategorized
  #     tokens collected under "General".
  defp token_groups(theme) do
    tokens = token_definitions(theme)

    if Enum.any?(tokens, &categorized?/1) do
      {:grouped, group_tokens(tokens)}
    else
      {:flat, tokens}
    end
  end

  defp categorized?(%{category: c}) when is_binary(c), do: String.trim(c) != ""
  defp categorized?(_), do: false

  defp token_category(tok),
    do: if(categorized?(tok), do: String.trim(tok.category), else: "General")

  defp group_tokens(tokens) do
    Enum.reduce(tokens, [], fn tok, acc ->
      cat = token_category(tok)

      case List.keyfind(acc, cat, 0) do
        nil -> acc ++ [{cat, [tok]}]
        {^cat, list} -> List.keyreplace(acc, cat, 0, {cat, list ++ [tok]})
      end
    end)
  end

  defp token_value(form, key) do
    case form[:theme_tokens].value do
      %{} = m -> Map.get(m, key) || Map.get(m, to_string(key)) || ""
      _ -> ""
    end
  end

  # The value shown in a token input: the per-site override if set, else the
  # manifest default — so the field (and especially the color picker, which
  # has no placeholder) reflects the effective value rather than a blank.
  defp token_display_value(form, tok) do
    case token_value(form, tok.key) do
      "" -> to_string(tok.default || "")
      value -> value
    end
  end

  # Value for a token <input>. Color has no placeholder, so it's pre-filled
  # with the effective value (override-or-default) to avoid showing black.
  # Every other input is left at the override only, so the manifest default
  # surfaces as the placeholder instead.
  defp token_input_value(form, %{type: "color"} = tok), do: token_display_value(form, tok)
  defp token_input_value(form, tok), do: token_value(form, tok.key)

  # Always give text inputs a placeholder: the manifest default, or the
  # token's label when there's no default.
  defp token_placeholder(tok) do
    case to_string(tok.default || "") do
      "" -> to_string(tok.label || "")
      default -> default
    end
  end

  defp html_input_type("color"), do: "color"
  defp html_input_type("number"), do: "number"
  defp html_input_type(_), do: "text"

  # Resolve a file token's stored upload id to the upload struct (for the
  # selected-file preview), or nil when unset / dangling.
  defp selected_upload(_uploads, value) when value in [nil, ""], do: nil

  defp selected_upload(uploads, value) do
    Enum.find(uploads, fn u -> to_string(u.id) == to_string(value) end)
  end

  defp selected_class(current, value) do
    if to_string(current) == to_string(value), do: " is-selected", else: ""
  end

  defp file_ext(filename) do
    filename |> Path.extname() |> String.trim_leading(".") |> String.upcase()
  end

  # Capitalize only the first letter for display (keeps the rest as-authored,
  # unlike String.capitalize/1 which lowercases the tail).
  defp capitalize_first(opt) do
    case to_string(opt) do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      other -> other
    end
  end

  # Rebuild the settings changeset with one theme token set/cleared, while
  # preserving the user's other in-progress (unsaved) field edits. A blank
  # value drops the key (mirrors normalize_theme_tokens).
  defp set_token(socket, key, value) do
    changeset = socket.assigns.changeset
    tokens = Ecto.Changeset.get_field(changeset, :theme_tokens) || %{}

    tokens =
      if value in [nil, ""],
        do: Map.delete(tokens, to_string(key)),
        else: Map.put(tokens, to_string(key), to_string(value))

    params = Map.put(editable_params(changeset), "theme_tokens", tokens)

    socket.assigns.site
    |> Sites.change_settings(params)
    |> Map.put(:action, :validate)
  end

  defp editable_params(changeset) do
    for field <- [:name, :title, :description, :theme_id, :theme_css_overrides, :homepage_page_id],
        into: %{} do
      {to_string(field), Ecto.Changeset.get_field(changeset, field)}
    end
  end

  defp cancel_picker_uploads(socket) do
    socket.assigns.uploads.picker_image.entries
    |> Enum.map(& &1.ref)
    |> Enum.reduce(socket, fn ref, acc -> cancel_upload(acc, :picker_image, ref) end)
  end

  defp error_to_string(:too_large), do: "Too large"
  defp error_to_string(:too_many_files), do: "Too many files"
  defp error_to_string(:not_accepted), do: "Unsupported file type"
  defp error_to_string(other), do: inspect(other)

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
                  <span class="theme-picker-card-name">{t.name}</span>
                </label>
                <.link class="theme-picker-card theme-picker-card-add" navigate={~p"/themes"}>
                  <span class="theme-picker-card-icon" aria-hidden="true">+</span>
                </.link>
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

            <%= case token_groups(@selected_theme) do %>
              <% {:flat, tokens} -> %>
                <div class="settings-fields">
                  <.token_field
                    :for={tok <- tokens}
                    tok={tok}
                    form={@form}
                    site={@site}
                    site_uploads={@site_uploads}
                  />
                </div>
              <% {:grouped, groups} -> %>
                <div class="token-groups">
                  <details
                    :for={{category, tokens} <- groups}
                    class="token-group"
                    open={@open_token_group == category}
                  >
                    <summary
                      class="token-group-summary"
                      phx-click="toggle_token_group"
                      phx-value-group={category}
                    >
                      {category}
                    </summary>
                    <div class="settings-fields">
                      <.token_field
                        :for={tok <- tokens}
                        tok={tok}
                        form={@form}
                        site={@site}
                        site_uploads={@site_uploads}
                      />
                    </div>
                  </details>
                </div>
            <% end %>
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

          <div class="wizard-footer">
            <.link navigate={~p"/#{@site.slug}"} class="btn">Cancel</.link>
            <button type="submit" class="btn btn-primary" data-shortcut="save">
              Save settings
            </button>
          </div>
        </.form>
      </div>

      <div
        :if={@picker_open?}
        class="dialog-backdrop"
        phx-window-keydown="close_picker"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_picker"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog">
          <header class="dialog-header">
            <h2>{if @picker_view == :upload, do: "Upload a file", else: "Choose a file"}</h2>
            <button type="button" phx-click="close_picker" class="dialog-close" aria-label="Close">
              &times;
            </button>
          </header>

          <div :if={@picker_view == :grid} class="dialog-body">
            <ul class="picker-grid">
              <li>
                <button
                  type="button"
                  class={"picker-card" <> selected_class(token_value(@form, @picker_token), "")}
                  phx-click="select_upload"
                  phx-value-id=""
                >
                  <span class="picker-thumb">
                    <span class="picker-none-icon" aria-hidden="true">⊘</span>
                  </span>
                  <span class="picker-name">No file</span>
                </button>
              </li>
              <li :for={u <- @site_uploads}>
                <button
                  type="button"
                  class={"picker-card" <> selected_class(token_value(@form, @picker_token), to_string(u.id))}
                  phx-click="select_upload"
                  phx-value-id={u.id}
                >
                  <span class="picker-thumb">
                    <img :if={Uploads.image?(u)} src={Uploads.url(u)} alt={u.filename} />
                    <span :if={not Uploads.image?(u)} class="file-badge">{file_ext(u.filename)}</span>
                  </span>
                  <span class="picker-name" title={u.filename}>{u.filename}</span>
                </button>
              </li>
              <li>
                <button type="button" class="picker-card picker-card-add" phx-click="open_uploader">
                  <span class="picker-thumb">
                    <span class="picker-add-icon" aria-hidden="true">+</span>
                  </span>
                  <span class="picker-name">Upload new</span>
                </button>
              </li>
            </ul>
          </div>

          <form
            :if={@picker_view == :upload}
            id="token-upload-form"
            phx-submit="upload_file"
            phx-change="validate_picker"
            class="dialog-body"
          >
            <label class="dropzone" phx-drop-target={@uploads.picker_image.ref}>
              <svg
                class="dropzone-icon"
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
              >
                <path
                  stroke-linecap="round"
                  stroke-linejoin="round"
                  d="M3 16.5v2.25A2.25 2.25 0 0 0 5.25 21h13.5A2.25 2.25 0 0 0 21 18.75V16.5M16.5 12 12 7.5m0 0L7.5 12m4.5-4.5v12"
                />
              </svg>
              <.live_file_input upload={@uploads.picker_image} />
              <p class="dropzone-headline">Drop an image here, or click to browse</p>
              <p class="muted">Up to 8MB. PNG, JPG, GIF, WebP, SVG, ICO, PDF.</p>
            </label>

            <ul :if={@uploads.picker_image.entries != []} class="upload-entries">
              <li :for={entry <- @uploads.picker_image.entries}>
                <span class="filename">{entry.client_name}</span>
                <span class="muted entry-progress">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel_picker_entry"
                  phx-value-ref={entry.ref}
                  class="btn btn-sm"
                >
                  Remove
                </button>
                <p
                  :for={err <- upload_errors(@uploads.picker_image, entry)}
                  class="error entry-error"
                >
                  {error_to_string(err)}
                </p>
              </li>
            </ul>

            <p :for={err <- upload_errors(@uploads.picker_image)} class="error">
              {error_to_string(err)}
            </p>

            <div class="dialog-footer">
              <button type="button" phx-click="back_to_grid" class="btn">Back</button>
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@uploads.picker_image.entries == []}
              >
                Upload &amp; use
              </button>
            </div>
          </form>
        </div>
      </div>
    </.shell>
    """
  end

  attr :tok, :map, required: true
  attr :form, :any, required: true
  attr :site, :map, required: true
  attr :site_uploads, :list, required: true

  defp token_field(assigns) do
    assigns =
      assign(
        assigns,
        :selected,
        selected_upload(assigns.site_uploads, token_value(assigns.form, assigns.tok.key))
      )

    ~H"""
    <label>
      {@tok.label}
      <div :if={@tok.type == "file"} class="token-file">
        <input
          type="hidden"
          name={"site[theme_tokens][" <> @tok.key <> "]"}
          value={token_value(@form, @tok.key)}
        />
        <span :if={@selected} class="token-file-thumb">
          <img :if={Uploads.image?(@selected)} src={Uploads.url(@selected)} alt="" />
          <span :if={not Uploads.image?(@selected)} class="file-badge file-badge-sm">
            {file_ext(@selected.filename)}
          </span>
        </span>
        <span :if={@selected} class="token-file-name">{@selected.filename}</span>
        <span :if={is_nil(@selected)} class="token-file-empty">No file selected</span>
        <div class="token-file-actions">
          <button
            type="button"
            class="btn btn-sm"
            phx-click="open_picker"
            phx-value-token={@tok.key}
          >
            {if @selected, do: "Change", else: "Choose file"}
          </button>
          <button
            :if={@selected}
            type="button"
            class="btn btn-sm"
            phx-click="clear_token"
            phx-value-token={@tok.key}
          >
            Remove
          </button>
        </div>
      </div>
      <select :if={@tok.type == "select"} name={"site[theme_tokens][" <> @tok.key <> "]"}>
        <option
          :for={opt <- @tok.options}
          value={opt}
          selected={to_string(opt) == to_string(token_display_value(@form, @tok))}
        >
          {capitalize_first(opt)}
        </option>
      </select>
      <input
        :if={@tok.type != "file" and @tok.type != "select"}
        type={html_input_type(@tok.type)}
        name={"site[theme_tokens][" <> @tok.key <> "]"}
        value={token_input_value(@form, @tok)}
        placeholder={token_placeholder(@tok)}
      />
      <small :if={@tok.type == "color" and @tok.default != ""}>
        Default: <code>{@tok.default}</code>
      </small>
    </label>
    """
  end
end
