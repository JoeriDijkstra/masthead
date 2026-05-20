defmodule LedgerWeb.Router do
  use LedgerWeb, :router

  import LedgerWeb.UserAuth, only: [fetch_current_user: 2, require_authenticated_user: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {LedgerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
  end

  scope "/", LedgerWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/login", SessionController, :new
    post "/login", SessionController, :create
    delete "/logout", SessionController, :delete

    get "/signup", RegistrationController, :new
    post "/signup", RegistrationController, :create

    get "/confirm/:token", ConfirmationController, :confirm
    post "/confirm", ConfirmationController, :create

    get "/reset-password", ResetPasswordController, :new
    post "/reset-password", ResetPasswordController, :create
    get "/reset-password/:token", ResetPasswordController, :edit
    put "/reset-password/:token", ResetPasswordController, :update
  end

  scope "/auth", LedgerWeb do
    pipe_through :browser

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
    post "/:provider/callback", AuthController, :callback
  end

  scope "/", LedgerWeb do
    pipe_through [:browser, :require_authenticated_user]

    get "/account", AccountController, :show
    post "/account/password", AccountController, :update_password
    post "/account/disable", AccountController, :disable

    live_session :authenticated,
      on_mount: [{LedgerWeb.UserAuth, :require_authenticated}] do
      live "/sites", AdminLive.SiteIndex, :index

      live "/themes", AdminLive.ThemeLibrary, :index

      live "/:site_slug", AdminLive.SiteDashboard, :show
      live "/:site_slug/settings", AdminLive.SiteSettings, :edit
      live "/:site_slug/domain", AdminLive.DomainSetup, :show

      live "/:site_slug/posts", AdminLive.PostIndex, :index
      live "/:site_slug/posts/new", AdminLive.PostForm, :new
      live "/:site_slug/posts/:id/edit", AdminLive.PostForm, :edit

      live "/:site_slug/pages", AdminLive.PageIndex, :index
      live "/:site_slug/pages/new", AdminLive.PageForm, :new
      live "/:site_slug/pages/:id/edit", AdminLive.PageForm, :edit

      live "/:site_slug/uploads", AdminLive.UploadIndex, :index
      live "/:site_slug/uploads/:id", AdminLive.UploadShow, :show
    end
  end

  if Application.compile_env(:ledger, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: LedgerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
