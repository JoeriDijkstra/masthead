defmodule MastheadWeb.AdminLive.Hooks do
  @moduledoc "On-mount hooks shared by admin LiveViews."
  import Phoenix.Component, only: [assign: 3]
  alias Phoenix.LiveView
  alias Masthead.Sites

  @doc """
  Load the site referenced by `:site_slug` in the URL params and verify
  the current user owns it. Halts the mount with a redirect to `/sites`
  otherwise.
  """
  def on_mount(:load_site, %{"site_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    # Admins can enter any site at owner level; everyone else is scoped to
    # the sites they own.
    site =
      if user.admin,
        do: Sites.get_site_for_admin_by_slug!(slug),
        else: Sites.get_user_site_by_slug!(user.id, slug)

    {:cont, assign(socket, :site, site)}
  rescue
    Ecto.NoResultsError ->
      {:halt,
       socket
       |> LiveView.put_flash(:error, "Site not found.")
       |> LiveView.redirect(to: "/sites")}
  end
end
