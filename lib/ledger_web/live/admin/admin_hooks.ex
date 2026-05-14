defmodule LedgerWeb.AdminLive.Hooks do
  @moduledoc "On-mount hooks shared by admin LiveViews."
  import Phoenix.Component, only: [assign: 3]
  alias Phoenix.LiveView
  alias Ledger.Sites

  @doc """
  Load the site referenced by `:site_slug` in the URL params and verify
  the current user owns it. Halts the mount with a redirect to `/sites`
  otherwise.
  """
  def on_mount(:load_site, %{"site_slug" => slug}, _session, socket) do
    user = socket.assigns.current_user

    case Sites.get_user_site_by_slug!(user.id, slug) do
      site -> {:cont, assign(socket, :site, site)}
    end
  rescue
    Ecto.NoResultsError ->
      {:halt,
       socket
       |> LiveView.put_flash(:error, "Site not found.")
       |> LiveView.redirect(to: "/sites")}
  end
end
