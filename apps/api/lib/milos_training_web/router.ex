defmodule MilosTrainingWeb.Router do
  use MilosTrainingWeb, :router

  pipeline :api do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: MilosTrainingWeb.ApiSpec)
  end

  pipeline :authenticated do
    plug(Guardian.Plug.Pipeline,
      module: MilosTraining.Infrastructure.Auth.Guardian,
      error_handler: MilosTrainingWeb.AuthErrorHandler
    )

    plug(Guardian.Plug.VerifyHeader, scheme: "Bearer")
    plug(Guardian.Plug.EnsureAuthenticated)
    plug(Guardian.Plug.LoadResource)
  end

  pipeline :auth_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 10, interval: 60_000)
  end

  pipeline :admin_only do
    plug(MilosTrainingWeb.Plugs.RequireRole, roles: [:admin])
  end

  pipeline :member_or_admin do
    plug(MilosTrainingWeb.Plugs.RequireRole, roles: [:member, :admin])
  end

  pipeline :athlete_or_admin do
    plug(MilosTrainingWeb.Plugs.RequireRole, roles: [:athlete, :admin])
  end

  pipeline :user_only do
    plug(MilosTrainingWeb.Plugs.RequireRole, roles: [:member, :athlete, :admin])
  end

  scope "/api" do
    pipe_through(:api)

    get("/health", MilosTrainingWeb.HealthController, :index)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
    get("/calendar/feed.ics", MilosTrainingWeb.CalendarFeedController, :feed)
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through([:api, :auth_rate_limited])

    post("/register", AuthController, :register)
    post("/login", AuthController, :login)
    post("/refresh", AuthController, :refresh)
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through([:api, :authenticated])

    get("/me", AuthController, :me)
  end

  scope "/api/admin", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :admin_only])

    patch("/users/:id/role", AdminUserController, :update_role)
    get("/search", AdminSearchController, :index)
    get("/analytics/summary", AdminAnalyticsController, :summary)
    get("/athletes", AdminUserController, :index_athletes)
    get("/scale-levels", AdminScaleLevelController, :index)
    put("/scale-levels", AdminScaleLevelController, :update)
    get("/workouts", AdminWorkoutController, :index)
    post("/workouts", AdminWorkoutController, :create)
    get("/workouts/:id", AdminWorkoutController, :show)
    patch("/workouts/:id/draft", AdminWorkoutController, :update_draft)
    post("/workouts/:id/publish", AdminWorkoutController, :publish)
    post("/workouts/:id/reopen", AdminWorkoutController, :reopen)
    post("/workouts/:id/duplicate", AdminWorkoutController, :duplicate)
    delete("/workouts/:id", AdminWorkoutController, :delete)
    post("/assigned-workouts", AdminAssignedWorkoutController, :create)
    patch("/assigned-workouts/:id", AdminAssignedWorkoutController, :update)
    delete("/assigned-workouts/:id", AdminAssignedWorkoutController, :delete)
    get("/challenges", AdminChallengeController, :index)
    post("/challenges", AdminChallengeController, :create)
    get("/challenges/:id", AdminChallengeController, :show)
    patch("/challenges/:id", AdminChallengeController, :update)
    delete("/challenges/:id", AdminChallengeController, :delete)
    get("/settings", AdminSettingsController, :show)
    patch("/settings", AdminSettingsController, :update)
    post("/schedule/slots", AdminScheduleController, :create_slot)
    patch("/schedule/slots/:id", AdminScheduleController, :update_slot)
    delete("/schedule/slots/:id", AdminScheduleController, :delete_slot)
    patch("/bookings/:id/approve", AdminScheduleController, :approve_booking)
    patch("/bookings/:id/reject", AdminScheduleController, :reject_booking)

    post(
      "/schedule/slots/:slot_id/attendance/:user_id",
      AdminScheduleController,
      :record_attendance
    )

    get("/athletes/:id/drill-down", AdminCoachingController, :drill_down)
    get("/finance/summary", AdminFinanceController, :summary)
    get("/finance/queues", AdminFinanceController, :operational_queues)
    get("/finance/packages", AdminFinanceController, :packages)
    post("/finance/packages", AdminFinanceController, :create_package)
    get("/finance/packages/:id", AdminFinanceController, :package)
    patch("/finance/packages/:id", AdminFinanceController, :update_package)
    get("/finance/members", AdminFinanceController, :members)
    get("/finance/members/:id", AdminFinanceController, :member)
    patch("/finance/members/:id", AdminFinanceController, :update_member)
    post("/finance/members/:id/packages", AdminFinanceController, :assign_package)
    post("/finance/members/:id/payments", AdminFinanceController, :record_payment)
    post("/finance/members/:id/invoices", AdminFinanceController, :create_invoice)

    post(
      "/finance/members/:id/invoices/renewal",
      AdminFinanceController,
      :generate_renewal_invoice
    )

    post("/finance/members/:id/credits", AdminFinanceController, :create_manual_credit)

    post(
      "/finance/members/:id/payments/:payment_id/credits",
      AdminFinanceController,
      :apply_credit_to_payment
    )

    post(
      "/finance/members/:id/payments/:payment_id/reversals",
      AdminFinanceController,
      :reverse_payment
    )

    post(
      "/finance/members/:id/invoices/:invoice_id/credits",
      AdminFinanceController,
      :apply_credit_to_invoice
    )

    post(
      "/finance/members/:id/credits/:credit_ledger_entry_id/reversals",
      AdminFinanceController,
      :reverse_credit_ledger_entry
    )

    patch("/finance/invoices/:id", AdminFinanceController, :update_invoice)
    patch("/finance/invoices/:id/issue", AdminFinanceController, :issue_invoice)
    patch("/finance/invoices/:id/void", AdminFinanceController, :void_invoice)
    post("/finance/invoices/:id/upload-url", AdminFinanceController, :invoice_upload_url)
    get("/finance/invoices/:id/download-url", AdminFinanceController, :invoice_download_url)

    post("/finance/members/:id/promotion-redemptions", AdminFinanceController, :redeem_promotion)
    get("/finance/promotions", AdminFinanceController, :promotions)
    post("/finance/promotions", AdminFinanceController, :create_promotion)
    get("/finance/promotions/:id/codes", AdminFinanceController, :promotion_codes)
    post("/finance/promotions/:id/codes", AdminFinanceController, :create_promotion_code)
    get("/finance/referral-programs", AdminFinanceController, :referral_programs)
    post("/finance/referral-programs", AdminFinanceController, :create_referral_program)
    get("/finance/referrals", AdminFinanceController, :referrals)
    post("/finance/referrals", AdminFinanceController, :create_referral)
    patch("/finance/referrals/:id/status", AdminFinanceController, :update_referral_status)
    get("/finance/referral-rewards", AdminFinanceController, :referral_rewards)

    patch(
      "/finance/referral-rewards/:id/status",
      AdminFinanceController,
      :update_referral_reward_status
    )

    post("/finance/referrals/:id/rewards", AdminFinanceController, :create_referral_reward)
    get("/reviews", AdminReviewController, :index)
    patch("/reviews/:id/status", AdminReviewController, :update_status)
    get("/wellbeing/injuries", AdminWellbeingController, :index)
    post("/wellbeing/users/:id/injuries", AdminWellbeingController, :create)
    patch("/wellbeing/injuries/:id/heal", AdminWellbeingController, :heal)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :member_or_admin])

    get("/schedule", ScheduleController, :index)
    post("/bookings", ScheduleController, :create_booking)
    delete("/bookings/:id", ScheduleController, :delete_booking)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :athlete_or_admin])

    get("/my-workouts", MyWorkoutController, :index)
    patch("/my-workouts/assignments/:id/reject", MyWorkoutController, :reject)
    patch("/my-workouts/assignments/:id/reschedule", MyWorkoutController, :reschedule)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :user_only])

    get("/calendar/export-links", CalendarFeedController, :links)
    post("/calendar/export-links/regenerate", CalendarFeedController, :regenerate_links)
    get("/landing", LandingController, :show)
    post("/landing/leaderboard-opt-in", LandingController, :update_leaderboard_preference)
    get("/notifications", NotificationController, :index)
    post("/notifications/read-all", NotificationController, :mark_all_read)
    post("/notifications/:id/read", NotificationController, :mark_read)
    post("/notifications/:id/click", NotificationController, :mark_clicked)
    get("/notifications/push-config", NotificationController, :push_config)
    post("/notifications/push-subscriptions", NotificationController, :create_push_subscription)

    post(
      "/notifications/push-subscriptions/status",
      NotificationController,
      :push_subscription_status
    )

    delete("/notifications/push-subscriptions", NotificationController, :delete_push_subscription)
    get("/reviews", ReviewController, :index)
    post("/reviews", ReviewController, :create)
    get("/wellbeing/injuries", WellbeingController, :index)
    post("/wellbeing/injuries", WellbeingController, :create)
    patch("/wellbeing/injuries/:id/heal", WellbeingController, :heal)
    get("/challenges/:id/leaderboard", ChallengeController, :leaderboard)
    post("/challenges/:id/opt_in", ChallengeController, :opt_in)
    delete("/challenges/:id/opt_in", ChallengeController, :opt_out)

    post("/threads", MessagingController, :create_thread)
    get("/threads", MessagingController, :list_threads)
    get("/threads/:id", MessagingController, :show_thread)
    get("/threads/:id/messages", MessagingController, :list_messages)
    post("/threads/:id/messages", MessagingController, :send_message)
    post("/threads/:id/read", MessagingController, :mark_read)
  end

  scope "/api/workouts", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :member_or_admin])

    get("/:id", WorkoutController, :show)
    get("/:id/scales", WorkoutController, :scales)
  end

  scope "/api/workouts", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :user_only])

    get("/:id/timer-sequence", ExecutionController, :timer_sequence)
  end

  scope "/api/executions", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :user_only])

    get("/", ExecutionController, :index)
    post("/", ExecutionController, :create)
    get("/:id", ExecutionController, :show)
    patch("/:id/progress", ExecutionController, :update_progress)
    post("/:id/notes", ExecutionController, :submit_note)
    patch("/:id/complete", ExecutionController, :complete)
  end

  if Application.compile_env(:milos_training, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: MilosTrainingWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  def open_api_spec do
    MilosTrainingWeb.ApiSpec.spec()
  end
end
