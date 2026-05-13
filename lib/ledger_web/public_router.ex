defmodule LedgerWeb.PublicRouter do
  @moduledoc """
  Router for site-on-subdomain requests. Dispatched to by the Endpoint when
  `LedgerWeb.Plugs.Subdomain` has resolved a site.
  """
  use LedgerWeb, :router

  pipeline :public do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_secure_browser_headers
  end

  scope "/", LedgerWeb do
    pipe_through :public

    get "/", PublicController, :index
    get "/posts/:slug", PublicController, :show_post
    get "/:slug", PublicController, :show_page
  end
end
