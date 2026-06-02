defmodule MastheadWeb.AdminLive.Console do
  @moduledoc "Platform-admin overview: manage all users, sites, and themes."
  use MastheadWeb, :live_view

  import MastheadWeb.AdminLive.Components

  alias Masthead.{Accounts, Actions, Sites, Themes}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Admin",
       tab: :users,
       action_modal?: false,
       action_site: nil
     )
     |> load_data()}
  end

  defp load_data(socket) do
    assign(socket,
      users: Accounts.list_all_users(),
      sites: Sites.list_all_sites(),
      themes: Themes.list_all_themes()
    )
  end

  @impl true
  def handle_event("switch_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, tab: String.to_existing_atom(tab))}
  end

  # ---- users ----

  def handle_event("verify_user", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_user!() |> Accounts.verify_user()
    {:noreply, socket |> put_flash(:info, "User verified.") |> load_data()}
  end

  def handle_event("disable_user", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_user!() |> Accounts.disable_user()
    {:noreply, socket |> put_flash(:info, "User disabled.") |> load_data()}
  end

  def handle_event("enable_user", %{"id" => id}, socket) do
    {:ok, _} = id |> Accounts.get_user!() |> Accounts.enable_user()
    {:noreply, socket |> put_flash(:info, "User re-enabled.") |> load_data()}
  end

  # ---- sites ----

  def handle_event("disable_site", %{"id" => id}, socket) do
    {:ok, _} = id |> Sites.get_site!() |> Sites.disable_site()
    {:noreply, socket |> put_flash(:info, "Site disabled.") |> load_data()}
  end

  def handle_event("enable_site", %{"id" => id}, socket) do
    {:ok, _} = id |> Sites.get_site!() |> Sites.enable_site()
    {:noreply, socket |> put_flash(:info, "Site enabled.") |> load_data()}
  end

  def handle_event("delete_site", %{"id" => id}, socket) do
    {:ok, _} = id |> Sites.get_site!() |> Sites.soft_delete_site()
    {:noreply, socket |> put_flash(:info, "Site deleted (recoverable).") |> load_data()}
  end

  def handle_event("restore_site", %{"id" => id}, socket) do
    {:ok, _} = id |> Sites.get_site!() |> Sites.restore_site()
    {:noreply, socket |> put_flash(:info, "Site restored.") |> load_data()}
  end

  def handle_event("open_action_modal", %{"site_id" => id}, socket) do
    {:noreply, assign(socket, action_modal?: true, action_site: Sites.get_site!(id))}
  end

  def handle_event("close_action_modal", _params, socket) do
    {:noreply, assign(socket, action_modal?: false, action_site: nil)}
  end

  def handle_event("create_action", %{"title" => title} = params, socket) do
    site = socket.assigns.action_site

    case Actions.create_custom_action(site, %{"title" => title, "message" => params["message"]}) do
      {:ok, _action} ->
        {:noreply,
         socket
         |> assign(action_modal?: false, action_site: nil)
         |> put_flash(:info, "Action added to #{site.name}.")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "A title is required.")}
    end
  end

  # ---- render ----

  @impl true
  def render(assigns) do
    ~H"""
    <.shell title="Admin" current_user={@current_user} flash={@flash} active={:admin}>
      <div class="admin-tabs">
        <button
          :for={{id, label} <- [{:users, "Users"}, {:sites, "Sites"}, {:themes, "Themes"}]}
          type="button"
          phx-click="switch_tab"
          phx-value-tab={id}
          class={"admin-tab" <> if(@tab == id, do: " is-active", else: "")}
        >
          {label}
        </button>
      </div>

      <div :if={@tab == :users} class="admin-table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Email</th>
              <th>Status</th>
              <th>Role</th>
              <th>Joined</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={u <- @users}>
              <td>{u.email}</td>
              <td>
                <span class={"pill " <> if(Accounts.User.confirmed?(u), do: "pill-ok", else: "pill-warn")}>
                  {if Accounts.User.confirmed?(u), do: "verified", else: "unverified"}
                </span>
                <span :if={Accounts.User.disabled?(u)} class="pill pill-danger">disabled</span>
              </td>
              <td>{if u.admin, do: "admin", else: "—"}</td>
              <td class="muted">{Calendar.strftime(u.inserted_at, "%b %-d, %Y")}</td>
              <td class="admin-row-actions">
                <button
                  :if={not Accounts.User.confirmed?(u)}
                  class="btn btn-sm"
                  phx-click="verify_user"
                  phx-value-id={u.id}
                >
                  Verify
                </button>
                <button
                  :if={not Accounts.User.disabled?(u)}
                  class="btn btn-sm"
                  phx-click="disable_user"
                  phx-value-id={u.id}
                  data-confirm={"Disable #{u.email}? Their sites stop resolving."}
                >
                  Disable
                </button>
                <button
                  :if={Accounts.User.disabled?(u)}
                  class="btn btn-sm"
                  phx-click="enable_user"
                  phx-value-id={u.id}
                >
                  Enable
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@tab == :sites} class="admin-table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th>Owner</th>
              <th>Status</th>
              <th>Add action</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={s <- @sites}>
              <td>{s.name}</td>
              <td class="muted">{s.slug}</td>
              <td class="muted">{s.owner && s.owner.email}</td>
              <td>
                <span :if={not is_nil(s.deleted_at)} class="pill pill-danger">deleted</span>
                <span
                  :if={is_nil(s.deleted_at) and not is_nil(s.disabled_at)}
                  class="pill pill-warn"
                >
                  disabled
                </span>
                <span :if={is_nil(s.deleted_at) and is_nil(s.disabled_at)} class="pill pill-ok">
                  active
                </span>
              </td>
              <td>
                <button
                  type="button"
                  class="btn btn-sm"
                  phx-click="open_action_modal"
                  phx-value-site_id={s.id}
                >
                  + Action
                </button>
              </td>
              <td class="admin-row-actions">
                <.link :if={is_nil(s.deleted_at)} navigate={~p"/#{s.slug}"} class="btn btn-sm">
                  Enter
                </.link>
                <button
                  :if={is_nil(s.disabled_at) and is_nil(s.deleted_at)}
                  class="btn btn-sm"
                  phx-click="disable_site"
                  phx-value-id={s.id}
                >
                  Disable
                </button>
                <button
                  :if={not is_nil(s.disabled_at) and is_nil(s.deleted_at)}
                  class="btn btn-sm"
                  phx-click="enable_site"
                  phx-value-id={s.id}
                >
                  Enable
                </button>
                <button
                  :if={is_nil(s.deleted_at)}
                  class="btn btn-sm btn-danger"
                  phx-click="delete_site"
                  phx-value-id={s.id}
                  data-confirm={"Delete #{s.name}? It's recoverable from here."}
                >
                  Delete
                </button>
                <button
                  :if={not is_nil(s.deleted_at)}
                  class="btn btn-sm"
                  phx-click="restore_site"
                  phx-value-id={s.id}
                >
                  Restore
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div :if={@tab == :themes} class="admin-table-wrap">
        <table class="table">
          <thead>
            <tr>
              <th>Name</th>
              <th>Slug</th>
              <th>Version</th>
              <th>Source</th>
              <th>Owner</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            <tr :for={t <- @themes}>
              <td>{t.name}</td>
              <td class="muted">{t.slug}</td>
              <td class="muted">{t.version}</td>
              <td>{t.source}</td>
              <td class="muted">{(t.owner && t.owner.email) || "—"}</td>
              <td class="admin-row-actions">
                <a
                  :if={t.source == "uploaded"}
                  href={~p"/admin/themes/#{t.id}/download"}
                  class="btn btn-sm"
                >
                  Download
                </a>
                <button
                  :if={t.source != "uploaded"}
                  type="button"
                  class="btn btn-sm"
                  disabled
                  title="Built-in themes live in the repo and can't be downloaded."
                >
                  Download
                </button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
      <div
        :if={@action_modal?}
        class="dialog-backdrop"
        phx-window-keydown="close_action_modal"
        phx-key="Escape"
      >
        <button
          type="button"
          phx-click="close_action_modal"
          class="dialog-close-overlay"
          aria-label="Close"
          tabindex="-1"
        >
        </button>
        <div class="dialog">
          <header class="dialog-header">
            <h2>Add action{if @action_site, do: " — #{@action_site.name}"}</h2>
            <button
              type="button"
              phx-click="close_action_modal"
              class="dialog-close"
              aria-label="Close"
            >
              &times;
            </button>
          </header>

          <form phx-submit="create_action" class="dialog-form">
            <label>
              Title <input type="text" name="title" autocomplete="off" required />
            </label>
            <label>
              Message <textarea
                name="message"
                rows="3"
                placeholder="Optional detail shown under the title."
              ></textarea>
              <small>Appears as a pending action in the owner's checklist.</small>
            </label>
            <div class="dialog-footer">
              <button type="button" phx-click="close_action_modal" class="btn">Cancel</button>
              <button type="submit" class="btn btn-primary">Add action</button>
            </div>
          </form>
        </div>
      </div>
    </.shell>
    """
  end
end
