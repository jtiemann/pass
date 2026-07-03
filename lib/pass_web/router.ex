defmodule PassWeb.Router do
  use PassWeb, :router

  import PassWeb.UserAuth

  pipeline :browser do
    # "json" is accepted too so the WebAuthn ceremony's fetch of
    # /users/passkeys/challenge (Accept: application/json) isn't rejected
    # with a 406 by content negotiation.
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {PassWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :put_content_security_policy
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Recent re-authentication required (passkeys, recovery codes).
  pipeline :sudo do
    plug :require_sudo_mode
  end

  # Content-Security-Policy with a per-request nonce for the one inline script
  # (the theme bootstrapper in the root layout). Everything else must come from
  # our own origin; ws:/wss: is needed for the LiveView socket.
  defp put_content_security_policy(conn, _opts) do
    nonce = Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)

    policy =
      "default-src 'self'; " <>
        "script-src 'self' 'nonce-#{nonce}'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data:; " <>
        "connect-src 'self' ws: wss:; " <>
        "object-src 'none'; " <>
        "base-uri 'self'; " <>
        "frame-ancestors 'self'; " <>
        "form-action 'self'"

    conn
    |> assign(:csp_nonce, nonce)
    |> Plug.Conn.put_resp_header("content-security-policy", policy)
  end

  scope "/", PassWeb do
    pipe_through :browser

    live_session :home, on_mount: [{PassWeb.UserAuth, :mount_current_scope}] do
      live "/", DashboardLive, :home
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", PassWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:pass, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: PassWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authentication routes

  scope "/", PassWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{PassWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/assets", AssetLive.Index, :index
      live "/assets/new", AssetLive.Form, :new
      live "/assets/:id", AssetLive.Show, :show
      live "/assets/:id/edit", AssetLive.Form, :edit
      live "/projections", ProjectionLive, :index
    end

    live_session :require_owner,
      on_mount: [
        {PassWeb.UserAuth, :require_authenticated},
        {PassWeb.UserAuth, :require_owner}
      ] do
      live "/users", UserLive.Admin, :index
      live "/audit", AuditLive.Index, :index
    end

    post "/users/update-password", UserSessionController, :update_password

    get "/assets/:asset_id/documents/:id/download", DocumentController, :download
  end

  # Passkey & recovery-code management: second-factor setup can redefine how the
  # account is protected, so it additionally requires a recent authentication.
  scope "/", PassWeb do
    pipe_through [:browser, :require_authenticated_user, :sudo]

    get "/users/passkeys", PasskeyController, :index
    get "/users/passkeys/challenge", PasskeyController, :challenge
    post "/users/passkeys", PasskeyController, :create
    delete "/users/passkeys/:id", PasskeyController, :delete
    post "/users/recovery-codes", PasskeyController, :recovery_codes
  end

  scope "/", PassWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{PassWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete

    # Second-factor step (user has passed factor one but is not yet logged in)
    get "/users/two-factor", TwoFactorController, :new
    post "/users/two-factor", TwoFactorController, :create
    post "/users/two-factor/recovery", TwoFactorController, :recovery
  end
end
