defmodule MastheadWeb.AdminLive.Marketplace do
  @moduledoc """
  The theme marketplace: an image-forward gallery of published themes you
  can install into your library. Lists published themes from other users
  (your own live in `/themes`). Filter by All / Verified / Community.
  """
  use MastheadWeb, :live_view

  import MastheadWeb.AdminLive.Components
  alias Masthead.Themes

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(page_title: "Marketplace", filter: :all, search: "", carousel: nil)
     |> load_themes()}
  end

  # Filter by verification status. No "private"/"built-in" here — the
  # marketplace is published themes only.
  defp filter_options,
    do: [{:all, "All"}, {:verified, "Verified"}, {:community, "Community"}]

  defp load_themes(%{assigns: a} = socket) do
    assign(socket,
      themes: Themes.list_marketplace(a.current_user.id, a.filter, a.search),
      installed: Themes.installed_theme_ids(a.current_user.id)
    )
  end

  @impl true
  def handle_event("switch_filter", %{"filter" => filter}, socket) do
    filter =
      Enum.find_value(filter_options(), :all, fn {value, _label} ->
        if Atom.to_string(value) == filter, do: value
      end)

    {:noreply, socket |> assign(filter: filter) |> load_themes()}
  end

  def handle_event("search", %{"query" => query}, socket) do
    {:noreply, socket |> assign(search: query) |> load_themes()}
  end

  def handle_event("install", %{"id" => id}, socket) do
    theme = Themes.get_theme!(id)
    {:ok, _} = Themes.install_theme(socket.assigns.current_user.id, theme)

    {:noreply,
     socket
     |> load_themes()
     |> put_flash(:info, "\"#{theme.name}\" added to your themes.")}
  end

  def handle_event("uninstall", %{"id" => id}, socket) do
    theme = Themes.get_theme!(id)
    {:ok, _} = Themes.uninstall_theme(socket.assigns.current_user.id, theme.id)

    {:noreply,
     socket
     |> load_themes()
     |> put_flash(:info, "\"#{theme.name}\" removed from your themes.")}
  end

  def handle_event("open_carousel", %{"id" => id}, socket) do
    id = String.to_integer(id)
    theme = Enum.find(socket.assigns.themes, &(&1.id == id))

    if theme && theme.images != [] do
      {:noreply, assign(socket, carousel: %{theme: theme, images: theme.images, index: 0})}
    else
      {:noreply, socket}
    end
  end

  def handle_event("close_carousel", _params, socket) do
    {:noreply, assign(socket, carousel: nil)}
  end

  def handle_event("carousel_nav", %{"dir" => dir}, socket) do
    %{images: images, index: index} = c = socket.assigns.carousel
    count = length(images)
    step = if dir == "next", do: 1, else: count - 1
    {:noreply, assign(socket, carousel: %{c | index: rem(index + step, count)})}
  end

  defp first_image(%{images: [image | _]}), do: image
  defp first_image(_), do: nil

  defp owner_email(%{owner: %Masthead.Accounts.User{email: email}}), do: email
  defp owner_email(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Marketplace" current_user={@current_user} flash={@flash} active={:marketplace}>
      <p class="page-intro">
        Browse themes the community has published and install the ones you
        like into your library. Verified themes are reviewed by us; community
        themes are published as-is.
      </p>

      <div class="admin-toolbar">
        <div class="admin-toolbar-row">
          <div class="admin-filters">
            <button
              :for={{value, label} <- filter_options()}
              type="button"
              class={["btn btn-sm", @filter == value && "btn-primary"]}
              phx-click="switch_filter"
              phx-value-filter={value}
            >
              {label}
            </button>
          </div>
          <form phx-change="search" class="admin-search">
            <input
              type="search"
              name="query"
              value={@search}
              placeholder="Search themes…"
              phx-debounce="300"
              autocomplete="off"
            />
          </form>
        </div>
      </div>

      <div :if={@themes == []} class="empty-state">
        <h2>Nothing here yet</h2>
        <p>
          {cond do
            @search != "" -> "No themes match \"#{@search}\"."
            @filter == :verified -> "No verified themes yet."
            @filter == :community -> "No community themes yet."
            true -> "No themes have been published to the marketplace yet."
          end}
        </p>
      </div>

      <ul :if={@themes != []} class="marketplace-grid">
        <li :for={t <- @themes} id={"marketplace-card-#{t.id}"}>
          <article class="marketplace-card">
            <div class="marketplace-thumb">
              <button
                :if={first_image(t)}
                type="button"
                class="marketplace-thumb-btn"
                phx-click="open_carousel"
                phx-value-id={t.id}
                aria-label={"View #{t.name} images"}
              >
                <img src={Themes.image_url(first_image(t))} alt={"#{t.name} preview"} />
                <span class="marketplace-thumb-zoom" aria-hidden="true">⤢</span>
              </button>
              <div :if={is_nil(first_image(t))} class="marketplace-thumb-empty">
                No preview
              </div>
              <div class="marketplace-card-tags">
                <.theme_badge theme={t} />
                <span class="chip chip-accent theme-card-version">v{t.version}</span>
              </div>
            </div>
            <div class="marketplace-card-meta">
              <div class="marketplace-card-id">
                <h3>{t.name}</h3>
                <span :if={owner_email(t)} class="marketplace-card-by">by {owner_email(t)}</span>
              </div>
              <button
                :if={not MapSet.member?(@installed, t.id)}
                type="button"
                class="btn btn-sm btn-primary"
                phx-click="install"
                phx-value-id={t.id}
              >
                Install
              </button>
              <button
                :if={MapSet.member?(@installed, t.id)}
                type="button"
                class="btn btn-sm"
                phx-click="uninstall"
                phx-value-id={t.id}
              >
                Installed ✓
              </button>
            </div>
          </article>
        </li>
      </ul>

      <div
        :if={@carousel}
        class="dialog-backdrop"
        phx-window-keydown="close_carousel"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_carousel"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog dialog-carousel">
          <header class="dialog-header">
            <div class="dialog-title">
              <h2>{@carousel.theme.name}</h2>
              <div class="theme-card-tags">
                <.theme_badge theme={@carousel.theme} />
                <span class="chip chip-accent theme-card-version">v{@carousel.theme.version}</span>
              </div>
            </div>
            <button type="button" phx-click="close_carousel" class="dialog-close" aria-label="Close">
              &times;
            </button>
          </header>

          <div class="carousel">
            <button
              :if={length(@carousel.images) > 1}
              type="button"
              class="carousel-nav carousel-prev"
              phx-click="carousel_nav"
              phx-value-dir="prev"
              aria-label="Previous image"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                aria-hidden="true"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 19.5 8.25 12l7.5-7.5" />
              </svg>
            </button>

            <div class="carousel-stage">
              <img
                src={Themes.image_url(Enum.at(@carousel.images, @carousel.index))}
                alt={"#{@carousel.theme.name} preview #{@carousel.index + 1}"}
              />
            </div>

            <button
              :if={length(@carousel.images) > 1}
              type="button"
              class="carousel-nav carousel-next"
              phx-click="carousel_nav"
              phx-value-dir="next"
              aria-label="Next image"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="2"
                stroke="currentColor"
                aria-hidden="true"
              >
                <path stroke-linecap="round" stroke-linejoin="round" d="m8.25 4.5 7.5 7.5-7.5 7.5" />
              </svg>
            </button>
          </div>

          <p :if={length(@carousel.images) > 1} class="carousel-counter">
            {@carousel.index + 1} / {length(@carousel.images)}
          </p>
        </div>
      </div>
    </.shell>
    """
  end
end
