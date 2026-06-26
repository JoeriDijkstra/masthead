defmodule MastheadWeb.AdminLive.ThemeLibrary do
  @moduledoc """
  Account-level theme library: lists every theme in the current user's
  library (built-ins + their own uploads + installed marketplace themes)
  and exposes the upload modal plus, for the user's own custom themes, a
  marketplace publish modal (upload preview images + publish/unpublish).
  """
  use MastheadWeb, :live_view

  import MastheadWeb.AdminLive.Components
  alias Masthead.Themes
  alias Masthead.Themes.Package

  @max_upload_bytes 5 * 1024 * 1024
  @max_image_bytes 8 * 1024 * 1024

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Themes",
       themes: themes_for(socket),
       modal_open?: false,
       upload_error: nil,
       publish_theme: nil,
       publish_images: [],
       publish_error: nil
     )
     |> allow_upload(:theme_zip,
       accept: ~w(.zip),
       max_entries: 1,
       max_file_size: @max_upload_bytes
     )
     |> allow_upload(:preview,
       accept: ~w(.png .jpg .jpeg .gif .webp),
       max_entries: 8,
       max_file_size: @max_image_bytes
     )}
  end

  @impl true
  def handle_event("open_modal", _params, socket) do
    {:noreply, assign(socket, modal_open?: true, upload_error: nil)}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, close_modal(socket)}
  end

  def handle_event("validate", _params, socket) do
    {:noreply, assign(socket, upload_error: nil)}
  end

  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :theme_zip, ref)}
  end

  def handle_event("upload", _params, socket) do
    owner_id = socket.assigns.current_user.id

    results =
      consume_uploaded_entries(socket, :theme_zip, fn %{path: path}, _entry ->
        case Package.install(path, owner_id) do
          {:ok, theme} -> {:ok, {:ok, theme}}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    case results do
      [{:ok, theme}] ->
        {:noreply,
         socket
         |> assign(themes: themes_for(socket), modal_open?: false, upload_error: nil)
         |> put_flash(:info, "Theme \"#{theme.name}\" installed.")}

      [{:error, reason}] ->
        {:noreply, assign(socket, upload_error: format_error(reason))}

      [] ->
        {:noreply, assign(socket, upload_error: "Please pick a .zip file first.")}
    end
  end

  def handle_event("delete", %{"id" => id}, socket) do
    theme = Themes.get_theme!(String.to_integer(id))

    cond do
      theme.source == "built_in" ->
        {:noreply, put_flash(socket, :error, "Built-in themes cannot be deleted.")}

      theme.owner_id != socket.assigns.current_user.id ->
        {:noreply, put_flash(socket, :error, "You can only delete themes you uploaded.")}

      true ->
        case Themes.delete_theme(theme) do
          {:ok, _} ->
            Masthead.Themes.Loader.invalidate(theme.id)

            {:noreply,
             socket
             |> assign(themes: themes_for(socket))
             |> put_flash(:info, "Theme deleted.")}

          {:error, {:in_use, names}} ->
            {:noreply, put_flash(socket, :error, theme_in_use_message(names))}

          {:error, _} ->
            {:noreply, put_flash(socket, :error, "Could not delete theme.")}
        end
    end
  end

  def handle_event("uninstall", %{"id" => id}, socket) do
    theme = Themes.get_theme!(String.to_integer(id))
    {:ok, _} = Themes.uninstall_theme(socket.assigns.current_user.id, theme.id)

    {:noreply,
     socket
     |> assign(themes: themes_for(socket))
     |> put_flash(:info, "\"#{theme.name}\" removed from your themes.")}
  end

  # ---- marketplace publish modal (own custom themes only) ----

  def handle_event("open_publish", %{"id" => id}, socket) do
    theme = Themes.get_theme!(String.to_integer(id))

    if publishable?(theme, socket.assigns.current_user) do
      {:noreply,
       assign(socket,
         publish_theme: theme,
         publish_images: Themes.list_theme_images(theme.id),
         publish_error: nil
       )}
    else
      {:noreply, put_flash(socket, :error, "Only your own custom themes can be published.")}
    end
  end

  def handle_event("close_publish", _params, socket) do
    {:noreply, close_publish(socket)}
  end

  def handle_event("validate_preview", _params, socket) do
    {:noreply, assign(socket, publish_error: nil)}
  end

  def handle_event("cancel-preview", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :preview, ref)}
  end

  def handle_event("save_previews", _params, socket) do
    theme = socket.assigns.publish_theme

    results =
      consume_uploaded_entries(socket, :preview, fn %{path: path}, entry ->
        case Themes.add_theme_image(theme, %{filename: entry.client_name, path: path}) do
          {:ok, _image} -> {:ok, :ok}
          {:error, reason} -> {:ok, {:error, reason}}
        end
      end)

    cond do
      results == [] ->
        {:noreply, assign(socket, publish_error: "Pick at least one image first.")}

      Enum.any?(results, &match?({:error, _}, &1)) ->
        {:noreply,
         socket
         |> assign(publish_images: Themes.list_theme_images(theme.id))
         |> assign(publish_error: "Some images couldn't be saved.")}

      true ->
        {:noreply,
         assign(socket,
           publish_images: Themes.list_theme_images(theme.id),
           publish_error: nil
         )}
    end
  end

  def handle_event("reorder_previews", %{"ids" => ids}, socket) do
    theme = socket.assigns.publish_theme
    ordered = Enum.map(ids, &String.to_integer/1)
    Themes.reorder_theme_images(theme.id, ordered)
    {:noreply, assign(socket, publish_images: Themes.list_theme_images(theme.id))}
  end

  def handle_event("remove_preview", %{"id" => id}, socket) do
    theme = socket.assigns.publish_theme
    image = Masthead.Repo.get!(Masthead.Themes.ThemeImage, id)

    if image.theme_id == theme.id do
      {:ok, _} = Themes.delete_theme_image(image)
      {:noreply, assign(socket, publish_images: Themes.list_theme_images(theme.id))}
    else
      {:noreply, socket}
    end
  end

  def handle_event("publish", _params, socket) do
    {:ok, theme} = Themes.publish_theme(socket.assigns.publish_theme)

    {:noreply,
     socket
     |> assign(publish_theme: theme, themes: themes_for(socket))
     |> put_flash(:info, "\"#{theme.name}\" is live on the marketplace.")}
  end

  def handle_event("unpublish", _params, socket) do
    {:ok, theme} = Themes.unpublish_theme(socket.assigns.publish_theme)

    {:noreply,
     socket
     |> assign(publish_theme: theme, themes: themes_for(socket))
     |> put_flash(:info, "\"#{theme.name}\" was removed from the marketplace.")}
  end

  # Build a flash naming the live sites that still reference a theme.
  defp theme_in_use_message(names) do
    count = length(names)
    site_word = if count == 1, do: "site", else: "sites"

    "Can't delete this theme — it's still in use by #{count} #{site_word}: " <>
      "#{Enum.join(names, ", ")}. Switch #{if count == 1, do: "it", else: "them"} to another theme first."
  end

  defp close_modal(socket) do
    refs = Enum.map(socket.assigns.uploads.theme_zip.entries, & &1.ref)

    socket =
      Enum.reduce(refs, socket, fn ref, acc ->
        cancel_upload(acc, :theme_zip, ref)
      end)

    assign(socket, modal_open?: false, upload_error: nil)
  end

  defp close_publish(socket) do
    refs = Enum.map(socket.assigns.uploads.preview.entries, & &1.ref)

    socket =
      Enum.reduce(refs, socket, fn ref, acc ->
        cancel_upload(acc, :preview, ref)
      end)

    assign(socket, publish_theme: nil, publish_images: [], publish_error: nil)
  end

  defp themes_for(%{assigns: %{current_user: user}}) do
    Themes.list_themes(user.id)
  end

  # A theme's "kind" from the current user's vantage point: their own
  # uploads are Custom, others' installed themes are from the Marketplace.
  defp theme_kind(%{source: "built_in"}, _user), do: :built_in
  defp theme_kind(%{owner_id: owner_id}, %{id: user_id}) when owner_id == user_id, do: :custom
  defp theme_kind(_theme, _user), do: :marketplace

  defp kind_label(:built_in), do: "Built-in"
  defp kind_label(:custom), do: "Custom"
  defp kind_label(:marketplace), do: "Marketplace"

  defp kind_class(:built_in), do: "chip chip-neutral"
  defp kind_class(:custom), do: "chip chip-accent"
  defp kind_class(:marketplace), do: "chip chip-marketplace"

  # The user can publish only their own custom (uploaded) themes.
  defp publishable?(theme, user), do: theme_kind(theme, user) == :custom

  # Installed marketplace themes can be removed from the library (this only
  # drops the install — the theme itself stays on the marketplace).
  defp uninstallable?(theme, user), do: theme_kind(theme, user) == :marketplace

  defp deletable?(theme, current_user) do
    theme.source == "uploaded" and theme.owner_id == current_user.id
  end

  defp format_error(reason) do
    case reason do
      {:archive_too_large, _, _} ->
        "Archive exceeds the 5 MB size cap."

      {:too_many_files, _, max} ->
        "Archive contains more than #{max} files."

      {:uncompressed_too_large, _, _} ->
        "Archive's uncompressed contents exceed the cap."

      {:archive_invalid, _} ->
        "That doesn't look like a valid zip file."

      :manifest_missing ->
        "manifest.json is missing from the archive."

      {:manifest_invalid, msgs} ->
        "manifest.json: " <> Enum.join(msgs, "; ")

      {:template_missing, name} ->
        "templates/#{name}.liquid is missing."

      {:template_invalid, name, _} ->
        "templates/#{name}.liquid failed to parse."

      :theme_css_missing ->
        "theme.css is missing."

      {:slug_reserved, slug} ->
        "Slug \"#{slug}\" is reserved."

      {:version_not_newer, slug, old, new} ->
        "Theme \"#{slug}\" is already at #{old}; uploaded version #{new} is not newer. " <>
          "Bump the version in manifest.json to update it."

      {:version_unparseable, v} ->
        "Version \"#{v}\" isn't valid semver (e.g. 1.2.0) — required to update an existing theme."

      {:db_write, _changeset} ->
        "Could not save the theme. Check the manifest and try again."

      {:disallowed_asset, name} ->
        "Asset \"#{name}\" has an unsupported file extension."

      {:traversal, name} ->
        "Unsafe path in entry \"#{name}\"."

      {:absolute_path, name} ->
        "Absolute path in entry \"#{name}\"."

      {:backslash, name} ->
        "Windows-style path separator in entry \"#{name}\"."

      other ->
        "Upload failed: #{inspect(other)}"
    end
  end

  defp error_to_string(:too_large), do: "File is too large."
  defp error_to_string(:not_accepted), do: "Wrong file type."
  defp error_to_string(:too_many_files), do: "Too many files."
  defp error_to_string(err), do: inspect(err)

  defp trash_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.6"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M14.74 9l-.346 9m-4.788 0L9.26 9m9.968-3.21c.342.052.682.107 1.022.166m-1.022-.165L18.16 19.673a2.25 2.25 0 0 1-2.244 2.077H8.084a2.25 2.25 0 0 1-2.244-2.077L4.772 5.79m14.456 0a48.108 48.108 0 0 0-3.478-.397m-12 .562c.34-.059.68-.114 1.022-.165m0 0a48.11 48.11 0 0 1 3.478-.397m7.5 0v-.916c0-1.18-.91-2.164-2.09-2.201a51.964 51.964 0 0 0-3.32 0c-1.18.037-2.09 1.022-2.09 2.201v.916m7.5 0a48.667 48.667 0 0 0-7.5 0"
      />
    </svg>
    """
  end

  defp uninstall_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.6"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15 12H9m12 0a9 9 0 1 1-18 0 9 9 0 0 1 18 0Z"
      />
    </svg>
    """
  end

  defp drag_handle_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      fill="currentColor"
      aria-hidden="true"
    >
      <path d="M9 5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm0 7a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm-1.5 8.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3ZM18 5a1.5 1.5 0 1 1-3 0 1.5 1.5 0 0 1 3 0Zm-1.5 8.5a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Zm0 7a1.5 1.5 0 1 0 0-3 1.5 1.5 0 0 0 0 3Z" />
    </svg>
    """
  end

  defp store_icon(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.6"
      stroke="currentColor"
      aria-hidden="true"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M13.5 21v-7.5a.75.75 0 0 1 .75-.75h3a.75.75 0 0 1 .75.75V21m-4.5 0H2.36m11.14 0H18m0 0h3.64m-1.39 0V9.349M3.75 21V9.349m0 0a3.001 3.001 0 0 0 3.75-.615A2.993 2.993 0 0 0 9.75 9.75c.896 0 1.7-.393 2.25-1.016a2.993 2.993 0 0 0 2.25 1.016c.896 0 1.7-.393 2.25-1.016a3.001 3.001 0 0 0 3.75.614m-16.5 0a3.004 3.004 0 0 1-.621-4.72l1.189-1.19A1.5 1.5 0 0 1 5.378 3h13.243a1.5 1.5 0 0 1 1.06.44l1.19 1.189a3 3 0 0 1-.621 4.72"
      />
    </svg>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Themes" current_user={@current_user} flash={@flash} active={:themes}>
      <:actions>
        <a
          href="https://github.com/JoeriDijkstra/masthead-template"
          target="_blank"
          rel="noopener"
          class="github-btn"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="currentColor"
            aria-hidden="true"
          >
            <path d="M12 .5C5.6.5.5 5.6.5 12c0 5.1 3.3 9.4 7.9 10.9.6.1.8-.2.8-.6v-2c-3.2.7-3.9-1.4-3.9-1.4-.5-1.3-1.3-1.7-1.3-1.7-1.1-.7.1-.7.1-.7 1.2.1 1.8 1.2 1.8 1.2 1 1.8 2.7 1.3 3.4 1 .1-.8.4-1.3.8-1.6-2.6-.3-5.3-1.3-5.3-5.8 0-1.3.5-2.3 1.2-3.1-.1-.3-.5-1.5.1-3.2 0 0 1-.3 3.3 1.2 1-.3 2-.4 3-.4s2 .1 3 .4c2.3-1.5 3.3-1.2 3.3-1.2.6 1.7.2 2.9.1 3.2.8.8 1.2 1.9 1.2 3.1 0 4.5-2.7 5.5-5.3 5.8.4.4.8 1.1.8 2.2v3.3c0 .3.2.7.8.6 4.6-1.5 7.9-5.9 7.9-10.9C23.5 5.6 18.4.5 12 .5z" />
          </svg>
          <span>Theme template</span>
        </a>
        <button type="button" phx-click="open_modal" class="btn btn-primary">+ Upload theme</button>
      </:actions>

      <p class="page-intro">
        Themes control how your sites look on the public web. Built-in
        themes are always available; upload your own Liquid theme
        packages, and publish them to the marketplace for others to use.
      </p>

      <div :if={@themes == []} class="empty-state">
        <h2>No themes yet</h2>
        <p>Upload a Liquid theme package to get started.</p>
        <button type="button" phx-click="open_modal" class="btn btn-primary">+ Upload theme</button>
      </div>

      <ul :if={@themes != []} class="theme-grid">
        <li :for={t <- @themes} id={"theme-card-#{t.id}"}>
          <article class="theme-card">
            <header class="theme-card-head">
              <h3 class="theme-card-title">{t.name}</h3>
              <div class="theme-card-tags">
                <span class={kind_class(theme_kind(t, @current_user))}>
                  {kind_label(theme_kind(t, @current_user))}
                </span>
                <span class="chip chip-accent theme-card-version">v{t.version}</span>
              </div>
            </header>

            <p :if={t.description != ""} class="theme-card-desc">{t.description}</p>

            <div class="theme-card-actions">
              <button
                :if={publishable?(t, @current_user)}
                type="button"
                phx-click="open_publish"
                phx-value-id={t.id}
                class={["theme-card-icon-btn", t.public && "is-live"]}
                aria-label={"Publish " <> t.name <> " to the marketplace"}
                title={
                  if t.public,
                    do: "Published — manage marketplace listing",
                    else: "Publish to the marketplace"
                }
              >
                <.store_icon />
              </button>

              <button
                :if={uninstallable?(t, @current_user)}
                type="button"
                phx-click="uninstall"
                phx-value-id={t.id}
                data-confirm={"Remove \"#{t.name}\" from your themes? You can reinstall it from the marketplace."}
                class="theme-card-icon-btn"
                aria-label={"Uninstall " <> t.name}
                title="Remove from your themes"
              >
                <.uninstall_icon />
              </button>
              <button
                :if={deletable?(t, @current_user)}
                type="button"
                phx-click="delete"
                phx-value-id={t.id}
                data-confirm={"Delete \"#{t.name}\"? Sites using it must switch first."}
                class="theme-card-icon-btn is-danger"
                aria-label={"Delete " <> t.name}
                title="Delete theme"
              >
                <.trash_icon />
              </button>
              <button
                :if={t.source == "built_in"}
                type="button"
                disabled
                class="theme-card-icon-btn"
                aria-label={"Delete " <> t.name}
                title="Built-in themes can't be deleted."
              >
                <.trash_icon />
              </button>
            </div>
          </article>
        </li>

        <li>
          <button type="button" phx-click="open_modal" class="theme-card theme-card-add">
            <span class="theme-card-add-icon" aria-hidden="true">+</span>
            <span class="theme-card-add-label">Upload theme</span>
          </button>
        </li>
      </ul>

      <div
        :if={@modal_open?}
        class="dialog-backdrop"
        phx-window-keydown="close_modal"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_modal"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog">
          <header class="dialog-header">
            <h2>Upload theme</h2>
            <button type="button" phx-click="close_modal" class="dialog-close" aria-label="Close">
              &times;
            </button>
          </header>

          <form id="theme-upload-form" phx-submit="upload" phx-change="validate" class="dialog-form">
            <label class="dropzone" phx-drop-target={@uploads.theme_zip.ref}>
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
              <.live_file_input upload={@uploads.theme_zip} />
              <p class="dropzone-headline">Drop a theme .zip here, or click to browse</p>
              <p class="muted">Up to 5 MB. Must contain a manifest, templates, and theme.css.</p>
            </label>

            <ul :if={@uploads.theme_zip.entries != []} class="upload-entries">
              <li :for={entry <- @uploads.theme_zip.entries}>
                <span class="entry-name">{entry.client_name}</span>
                <span class="muted entry-progress">{entry.progress}%</span>
                <button
                  type="button"
                  phx-click="cancel-upload"
                  phx-value-ref={entry.ref}
                  class="btn btn-sm"
                >
                  Remove
                </button>
                <p :for={err <- upload_errors(@uploads.theme_zip, entry)} class="error entry-error">
                  {error_to_string(err)}
                </p>
              </li>
            </ul>

            <p :for={err <- upload_errors(@uploads.theme_zip)} class="error">
              {error_to_string(err)}
            </p>
            <p :if={@upload_error} class="error">{@upload_error}</p>

            <footer class="dialog-footer">
              <button type="button" phx-click="close_modal" class="btn">Cancel</button>
              <button
                type="submit"
                class="btn btn-primary"
                disabled={@uploads.theme_zip.entries == []}
              >
                Install
              </button>
            </footer>
          </form>
        </div>
      </div>

      <div
        :if={@publish_theme}
        class="dialog-backdrop"
        phx-window-keydown="close_publish"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_publish"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog">
          <header class="dialog-header">
            <h2>Publish — {@publish_theme.name}</h2>
            <button type="button" phx-click="close_publish" class="dialog-close" aria-label="Close">
              &times;
            </button>
          </header>

          <div class="dialog-form">
            <p class="muted">
              Add a few preview images — the marketplace shows them front and
              center — then publish.
            </p>

            <p :if={@publish_images != []} class="muted preview-list-hint">
              Drag to reorder — the first image leads the marketplace listing.
            </p>
            <ul
              :if={@publish_images != []}
              id="preview-sortable"
              phx-hook="SortableList"
              data-sortable-event="reorder_previews"
              class="preview-list"
            >
              <li
                :for={img <- @publish_images}
                id={"preview-row-#{img.id}"}
                draggable="true"
                data-sortable-id={img.id}
                class="preview-row"
              >
                <span class="preview-drag" aria-hidden="true"><.drag_handle_icon /></span>
                <img
                  src={Themes.image_url(img)}
                  alt={"#{@publish_theme.name} preview"}
                  class="preview-thumb"
                />
                <span class="preview-row-spacer"></span>
                <button
                  type="button"
                  class="btn btn-sm btn-danger"
                  phx-click="remove_preview"
                  phx-value-id={img.id}
                  data-confirm="Remove this image?"
                >
                  Remove
                </button>
              </li>
            </ul>

            <form
              id="preview-upload-form"
              phx-submit="save_previews"
              phx-change="validate_preview"
            >
              <label class="dropzone" phx-drop-target={@uploads.preview.ref}>
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
                <.live_file_input upload={@uploads.preview} />
                <p class="dropzone-headline">Drop preview images here, or click to browse</p>
                <p class="muted">PNG, JPG, GIF or WebP. Up to 8 images, 8 MB each.</p>
              </label>

              <ul :if={@uploads.preview.entries != []} class="upload-entries">
                <li :for={entry <- @uploads.preview.entries}>
                  <span class="entry-name">{entry.client_name}</span>
                  <span class="muted entry-progress">{entry.progress}%</span>
                  <button
                    type="button"
                    phx-click="cancel-preview"
                    phx-value-ref={entry.ref}
                    class="btn btn-sm"
                  >
                    Remove
                  </button>
                  <p :for={err <- upload_errors(@uploads.preview, entry)} class="error entry-error">
                    {error_to_string(err)}
                  </p>
                </li>
              </ul>

              <p :for={err <- upload_errors(@uploads.preview)} class="error">
                {error_to_string(err)}
              </p>
              <p :if={@publish_error} class="error">{@publish_error}</p>

              <div class="dialog-form-inline">
                <button
                  type="submit"
                  class="btn"
                  disabled={@uploads.preview.entries == []}
                >
                  Add images
                </button>
              </div>
            </form>

            <footer class="dialog-footer">
              <button type="button" phx-click="close_publish" class="btn">Done</button>
              <button
                :if={not @publish_theme.public}
                type="button"
                phx-click="publish"
                class="btn btn-primary"
              >
                Publish to marketplace
              </button>
              <button
                :if={@publish_theme.public}
                type="button"
                phx-click="unpublish"
                class="btn btn-danger"
              >
                Unpublish
              </button>
            </footer>
          </div>
        </div>
      </div>
    </.shell>
    """
  end
end
