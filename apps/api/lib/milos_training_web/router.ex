defmodule MilosTrainingWeb.Router do
  use MilosTrainingWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: MilosTrainingWeb.ApiSpec
  end

  pipeline :authenticated do
    plug Guardian.Plug.Pipeline,
      module: MilosTraining.Infrastructure.Auth.Guardian,
      error_handler: MilosTrainingWeb.AuthErrorHandler

    plug Guardian.Plug.VerifyHeader, scheme: "Bearer"
    plug Guardian.Plug.EnsureAuthenticated
    plug Guardian.Plug.LoadResource
  end

  pipeline :auth_rate_limited do
    plug MilosTrainingWeb.Plugs.RateLimit, max: 10, interval: 60_000
  end

  pipeline :admin_only do
    plug MilosTrainingWeb.Plugs.RequireRole, roles: [:admin]
  end

  pipeline :member_or_admin do
    plug MilosTrainingWeb.Plugs.RequireRole, roles: [:member, :admin]
  end

  pipeline :athlete_or_admin do
    plug MilosTrainingWeb.Plugs.RequireRole, roles: [:athlete, :admin]
  end

  pipeline :user_only do
    plug MilosTrainingWeb.Plugs.RequireRole, roles: [:member, :athlete, :admin]
  end

  scope "/api" do
    pipe_through :api

    get "/health", MilosTrainingWeb.HealthController, :index
    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through [:api, :auth_rate_limited]

    post "/register", AuthController, :register
    post "/login", AuthController, :login
    post "/refresh", AuthController, :refresh
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through [:api, :authenticated]

    get "/me", AuthController, :me
  end

  scope "/api/admin", MilosTrainingWeb do
    pipe_through [:api, :authenticated, :admin_only]

    patch "/users/:id/role", AdminUserController, :update_role
    get "/scale-levels", AdminScaleLevelController, :index
    put "/scale-levels", AdminScaleLevelController, :update
    get "/workouts", AdminWorkoutController, :index
    post "/workouts", AdminWorkoutController, :create
    get "/workouts/:id", AdminWorkoutController, :show
    patch "/workouts/:id/draft", AdminWorkoutController, :update_draft
    post "/workouts/:id/publish", AdminWorkoutController, :publish
  end

  scope "/api/workouts", MilosTrainingWeb do
    pipe_through [:api, :authenticated, :member_or_admin]

    get "/:id", WorkoutController, :show
    get "/:id/scales", WorkoutController, :scales
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:milos_training, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: MilosTrainingWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  def open_api_spec do
    MilosTrainingWeb.ApiSpec.spec()
  end
end
