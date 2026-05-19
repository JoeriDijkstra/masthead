defmodule LedgerWeb.AdminLive.Components do
  @moduledoc "Shared HEEx components for admin LiveViews."
  use Phoenix.Component
  use LedgerWeb, :verified_routes

  alias Ledger.Accounts.User

  attr :title, :string, default: nil
  attr :site, :map, default: nil
  attr :current_user, :map, default: nil
  attr :flash, :map, default: %{}

  attr :active, :atom,
    default: nil,
    doc: ":overview | :posts | :pages | :uploads | :settings | :sites | :themes"

  slot :inner_block, required: true
  slot :actions

  def shell(assigns) do
    ~H"""
    <div class="admin-shell">
      <aside class="admin-sidebar">
        <div class="sidebar-brand">
          <.link navigate={~p"/sites"} class="brand">
            <span class="brand-mark">●</span>
            <span class="brand-name">Ledger</span>
          </.link>
          <p class="sidebar-version">v{Application.spec(:ledger, :vsn)}</p>
          <p :if={@site} class="sidebar-site">{@site.name}</p>
        </div>

        <nav class="sidebar-nav">
          <%= if @site do %>
            <.nav_link href={~p"/#{@site.slug}"} label="Overview" active={@active == :overview}>
              <.icon_home />
            </.nav_link>
            <.nav_link href={~p"/#{@site.slug}/posts"} label="Posts" active={@active == :posts}>
              <.icon_doc />
            </.nav_link>
            <.nav_link href={~p"/#{@site.slug}/pages"} label="Pages" active={@active == :pages}>
              <.icon_page />
            </.nav_link>
            <.nav_link href={~p"/#{@site.slug}/uploads"} label="Uploads" active={@active == :uploads}>
              <.icon_image />
            </.nav_link>
            <.nav_link
              href={~p"/#{@site.slug}/settings"}
              label="Settings"
              active={@active == :settings}
            >
              <.icon_cog />
            </.nav_link>

            <div class="sidebar-divider"></div>

            <a class="nav-item nav-external" href={site_url(@site)} target="_blank" rel="noopener">
              <.icon_external />
              <span>View site</span>
            </a>

            <.nav_link href={~p"/sites"} label="All sites" active={false}>
              <.icon_grid />
            </.nav_link>
          <% else %>
            <.nav_link href={~p"/sites"} label="Your sites" active={@active == :sites}>
              <.icon_grid />
            </.nav_link>

            <.nav_link href={~p"/themes"} label="Themes" active={@active == :themes}>
              <.icon_palette />
            </.nav_link>
          <% end %>
        </nav>

        <div :if={@current_user} class="sidebar-user">
          <div class="user-avatar">{user_initial(@current_user)}</div>
          <.link navigate={~p"/account"} class="user-email" title="Account settings">
            {@current_user.email}
          </.link>
          <.link href={~p"/logout"} method="delete" class="logout-link" title="Log out">
            <.icon_logout />
          </.link>
        </div>
      </aside>

      <main class="admin-content">
        <.unconfirmed_banner :if={@current_user} user={@current_user} />

        <div :if={@flash != %{} and Phoenix.Flash.get(@flash, :info)} class="admin-flash">
          <p class="flash flash-info">{Phoenix.Flash.get(@flash, :info)}</p>
        </div>
        <div :if={@flash != %{} and Phoenix.Flash.get(@flash, :error)} class="admin-flash">
          <p class="flash flash-error">{Phoenix.Flash.get(@flash, :error)}</p>
        </div>

        <div :if={@title || @actions != []} class="page-head">
          <h1 :if={@title}>{@title}</h1>
          <div class="actions">{render_slot(@actions)}</div>
        </div>

        {render_slot(@inner_block)}
      </main>
    </div>
    """
  end

  attr :user, :map, required: true

  @doc """
  Persistent reminder shown to signed-in users whose email is not yet
  confirmed. Renders nothing once confirmed. The resend action posts to
  `/confirm`; the controller is enumeration-safe.
  """
  def unconfirmed_banner(assigns) do
    ~H"""
    <div :if={not User.confirmed?(@user)} class="account-banner" role="status">
      <p>
        Please confirm your email address. We sent a link to <strong>{@user.email}</strong>. Unconfirmed accounts are disabled after 7 days.
      </p>
      <.link href={~p"/confirm"} method="post" class="account-banner-btn">
        Resend confirmation
      </.link>
    </div>
    """
  end

  attr :href, :string, required: true
  attr :label, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  defp nav_link(assigns) do
    ~H"""
    <.link navigate={@href} class={"nav-item" <> if(@active, do: " active", else: "")}>
      {render_slot(@inner_block)}
      <span>{@label}</span>
    </.link>
    """
  end

  attr :rest, :global
  attr :variant, :string, default: "primary"
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button class={"btn btn-" <> @variant} {@rest}>{render_slot(@inner_block)}</button>
    """
  end

  @doc """
  Renders the Markdown / HTML format picker as a pair of cards.

  * `selected` — `"markdown"` or `"html"` to mark a card as active, or `nil` for none
  * `locked`   — when true, cards are non-interactive (no `phx-click`) and
                 the un-selected card is disabled. Used on edit pages where
                 format is fixed at creation.
  """
  attr :selected, :string, default: nil
  attr :locked, :boolean, default: false
  attr :allow_blog, :boolean, default: false

  def format_cards(assigns) do
    ~H"""
    <div class="format-cards">
      <button
        type="button"
        phx-click={!@locked && "choose_format"}
        phx-value-format="markdown"
        disabled={@locked && @selected != "markdown"}
        class={card_classes("markdown", @selected, @locked)}
      >
        <div class="format-icon">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <rect x="3" y="6" width="18" height="12" rx="2" />
            <path d="M7 14V10l2.5 3L12 10v4" stroke-linecap="round" stroke-linejoin="round" />
            <path d="M16 10v4M14.5 12.5L16 14l1.5-1.5" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </div>
        <h3>Markdown</h3>
        <p>Plain text with simple formatting. Headings, lists, links, code, images.</p>
        <span class="format-pill">Recommended</span>
      </button>

      <button
        type="button"
        phx-click={!@locked && "choose_format"}
        phx-value-format="html"
        disabled={@locked && @selected != "html"}
        class={card_classes("html", @selected, @locked)}
      >
        <div class="format-icon">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <polyline points="16 18 22 12 16 6" stroke-linecap="round" stroke-linejoin="round" />
            <polyline points="8 6 2 12 8 18" stroke-linecap="round" stroke-linejoin="round" />
          </svg>
        </div>
        <h3>HTML</h3>
        <p>
          Raw HTML for full control. Sanitized on render — scripts and unsafe attributes are stripped.
        </p>
        <span class="format-pill format-pill-muted">Advanced</span>
      </button>

      <button
        :if={@allow_blog}
        type="button"
        phx-click={!@locked && "choose_format"}
        phx-value-format="blog"
        disabled={@locked && @selected != "blog"}
        class={card_classes("blog", @selected, @locked)}
      >
        <div class="format-icon">
          <svg
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 24 24"
            fill="none"
            stroke="currentColor"
            stroke-width="1.5"
          >
            <path
              stroke-linecap="round"
              stroke-linejoin="round"
              d="M3.75 6h16.5M3.75 12h16.5m-16.5 6h16.5"
            />
          </svg>
        </div>
        <h3>Blog</h3>
        <p>
          Renders the list of published posts. Body is shown as Markdown intro above the list. Set as homepage to make this the front page.
        </p>
        <span class="format-pill format-pill-muted">List</span>
      </button>
    </div>
    """
  end

  defp card_classes(key, selected, locked) do
    [
      "format-card",
      selected == key && "format-card-selected",
      locked && selected != key && "format-card-disabled"
    ]
  end

  attr :changeset, :map, required: true
  attr :show, :boolean, default: false

  def error_list(assigns) do
    ~H"""
    <ul :if={@show and @changeset.errors != []} class="errors">
      <li :for={{field, {msg, _}} <- @changeset.errors}>{field}: {msg}</li>
    </ul>
    """
  end

  defp user_initial(%{email: email}) when is_binary(email) do
    email |> String.first() |> String.upcase()
  end

  defp user_initial(_), do: "?"

  @doc false
  # Builds the public URL for a site based on `:ledger, :site_url`:
  #
  #   * `scheme: "http", host: "lvh.me", port: 4000`        -> http://slug.lvh.me:4000
  #   * `scheme: "https", host: "yourdomain.com", port: nil` -> https://slug.yourdomain.com
  defp site_url(%{custom_domain: domain, custom_domain_status: "active"})
       when is_binary(domain),
       do: "https://#{domain}"

  defp site_url(site) do
    cfg = Application.get_env(:ledger, :site_url, scheme: "http", host: "lvh.me", port: 4000)
    scheme = Keyword.fetch!(cfg, :scheme)
    host = Keyword.fetch!(cfg, :host)
    port = Keyword.get(cfg, :port)

    port_segment =
      cond do
        is_nil(port) -> ""
        scheme == "http" and port == 80 -> ""
        scheme == "https" and port == 443 -> ""
        true -> ":#{port}"
      end

    "#{scheme}://#{site.slug}.#{host}#{port_segment}"
  end

  # ---- Icons (heroicons outline, inlined) ----

  defp icon_home(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M2.25 12 12 2.25 21.75 12M4.5 9.75v9.75A1.5 1.5 0 0 0 6 21h3.75v-6h4.5v6H18a1.5 1.5 0 0 0 1.5-1.5V9.75"
      />
    </svg>
    """
  end

  defp icon_doc(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M16.862 4.487 18.549 2.8a2.121 2.121 0 1 1 3 3L19.862 7.487m-3-3L6.34 15.013a4.5 4.5 0 0 0-1.13 1.897l-.943 3.18 3.18-.943a4.5 4.5 0 0 0 1.897-1.13L19.862 7.487m-3-3 3 3"
      />
    </svg>
    """
  end

  defp icon_page(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M19.5 14.25v-2.625a3.375 3.375 0 0 0-3.375-3.375h-1.5A1.125 1.125 0 0 1 13.5 7.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H8.25m2.25 0H5.625c-.621 0-1.125.504-1.125 1.125v17.25c0 .621.504 1.125 1.125 1.125h12.75c.621 0 1.125-.504 1.125-1.125V11.25a9 9 0 0 0-9-9Z"
      />
    </svg>
    """
  end

  defp icon_image(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="m2.25 15.75 5.159-5.159a2.25 2.25 0 0 1 3.182 0l5.159 5.159m-1.5-1.5 1.409-1.409a2.25 2.25 0 0 1 3.182 0l2.909 2.909m-18 3.75h16.5a1.5 1.5 0 0 0 1.5-1.5V6a1.5 1.5 0 0 0-1.5-1.5H3.75A1.5 1.5 0 0 0 2.25 6v12a1.5 1.5 0 0 0 1.5 1.5Zm10.5-11.25h.008v.008h-.008V8.25Zm.375 0a.375.375 0 1 1-.75 0 .375.375 0 0 1 .75 0Z"
      />
    </svg>
    """
  end

  defp icon_cog(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9.594 3.94c.09-.542.56-.94 1.11-.94h2.593c.55 0 1.02.398 1.11.94l.213 1.281c.063.374.313.686.645.87.074.04.147.083.22.127.325.196.72.257 1.075.124l1.217-.456a1.125 1.125 0 0 1 1.37.49l1.296 2.247a1.125 1.125 0 0 1-.26 1.431l-1.003.827c-.293.241-.438.613-.43.992a7.723 7.723 0 0 1 0 .255c-.008.378.137.75.43.991l1.004.827c.424.35.534.955.26 1.43l-1.298 2.247a1.125 1.125 0 0 1-1.369.491l-1.217-.456c-.355-.133-.75-.072-1.076.124a6.47 6.47 0 0 1-.22.128c-.331.183-.581.495-.644.869l-.213 1.281c-.09.543-.56.94-1.11.94h-2.594c-.55 0-1.019-.398-1.11-.94l-.213-1.281c-.062-.374-.312-.686-.644-.87a6.52 6.52 0 0 1-.22-.127c-.325-.196-.72-.257-1.076-.124l-1.217.456a1.125 1.125 0 0 1-1.369-.49l-1.297-2.247a1.125 1.125 0 0 1 .26-1.431l1.004-.827c.292-.24.437-.613.43-.991a6.932 6.932 0 0 1 0-.255c.007-.38-.138-.751-.43-.992l-1.004-.827a1.125 1.125 0 0 1-.26-1.43l1.297-2.247a1.125 1.125 0 0 1 1.37-.491l1.216.456c.356.133.751.072 1.076-.124.072-.044.146-.087.22-.128.332-.183.582-.495.644-.869l.214-1.28Z"
      />
      <path stroke-linecap="round" stroke-linejoin="round" d="M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0Z" />
    </svg>
    """
  end

  defp icon_external(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M13.5 6H5.25A2.25 2.25 0 0 0 3 8.25v10.5A2.25 2.25 0 0 0 5.25 21h10.5A2.25 2.25 0 0 0 18 18.75V10.5m-10.5 6L21 3m0 0h-5.25M21 3v5.25"
      />
    </svg>
    """
  end

  defp icon_grid(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M3.75 6A2.25 2.25 0 0 1 6 3.75h2.25A2.25 2.25 0 0 1 10.5 6v2.25a2.25 2.25 0 0 1-2.25 2.25H6a2.25 2.25 0 0 1-2.25-2.25V6ZM3.75 15.75A2.25 2.25 0 0 1 6 13.5h2.25a2.25 2.25 0 0 1 2.25 2.25V18a2.25 2.25 0 0 1-2.25 2.25H6A2.25 2.25 0 0 1 3.75 18v-2.25ZM13.5 6a2.25 2.25 0 0 1 2.25-2.25H18A2.25 2.25 0 0 1 20.25 6v2.25A2.25 2.25 0 0 1 18 10.5h-2.25a2.25 2.25 0 0 1-2.25-2.25V6ZM13.5 15.75a2.25 2.25 0 0 1 2.25-2.25H18a2.25 2.25 0 0 1 2.25 2.25V18A2.25 2.25 0 0 1 18 20.25h-2.25A2.25 2.25 0 0 1 13.5 18v-2.25Z"
      />
    </svg>
    """
  end

  defp icon_logout(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M15.75 9V5.25A2.25 2.25 0 0 0 13.5 3h-6a2.25 2.25 0 0 0-2.25 2.25v13.5A2.25 2.25 0 0 0 7.5 21h6a2.25 2.25 0 0 0 2.25-2.25V15m3 0 3-3m0 0-3-3m3 3H9"
      />
    </svg>
    """
  end

  defp icon_palette(assigns) do
    ~H"""
    <svg
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      stroke-width="1.5"
      stroke="currentColor"
      class="icon"
    >
      <path
        stroke-linecap="round"
        stroke-linejoin="round"
        d="M9.53 16.122a3 3 0 0 0-5.78 1.128 2.25 2.25 0 0 1-2.4 2.245 4.5 4.5 0 0 0 8.4-2.245c0-.399-.078-.78-.22-1.128Zm0 0a15.998 15.998 0 0 0 3.388-1.62m-5.043-.025a15.994 15.994 0 0 1 1.622-3.395m3.42 3.42a15.995 15.995 0 0 0 4.764-4.648l3.876-5.814a1.151 1.151 0 0 0-1.597-1.597L14.146 6.32a15.996 15.996 0 0 0-4.649 4.763m3.42 3.42a6.776 6.776 0 0 0-3.42-3.42"
      />
    </svg>
    """
  end
end
