defmodule MastheadWeb.SiteDispatcher do
  @moduledoc """
  Endpoint-level dispatcher. Runs the subdomain plug, and if a site was
  resolved, dispatches the request to `MastheadWeb.PublicRouter` and halts.
  Otherwise the connection falls through to `MastheadWeb.Router`.
  """
  @behaviour Plug

  alias MastheadWeb.{Plugs, PublicRouter}

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = Plugs.Subdomain.call(conn, [])

    cond do
      conn.halted ->
        conn

      conn.assigns[:current_site] ->
        conn = PublicRouter.call(conn, PublicRouter.init([]))
        Plug.Conn.halt(conn)

      true ->
        conn
    end
  end
end
