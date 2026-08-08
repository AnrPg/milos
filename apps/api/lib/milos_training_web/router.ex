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
    plug(MilosTrainingWeb.Plugs.LoggerUserMetadata)
    plug(MilosTrainingWeb.Plugs.AssignUserContext)
  end

  pipeline :auth_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 10, interval: 60_000)
  end

  pipeline :invitation_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 10, interval: 60_000)
  end

  pipeline :authenticated_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 600, interval: 60_000, bucket: "authenticated")
  end

  pipeline :tenant_write_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 120,
      interval: 60_000,
      bucket: "tenant-writes",
      methods: ["POST", "PATCH", "PUT", "DELETE"]
    )
  end

  pipeline :upload_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 20,
      interval: 300_000,
      bucket: "uploads",
      methods: ["POST"]
    )
  end

  pipeline :messaging_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "messaging",
      methods: ["POST"]
    )
  end

  pipeline :execution_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 240,
      interval: 60_000,
      bucket: "execution",
      methods: ["POST", "PATCH"]
    )
  end

  pipeline :notification_write_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 120,
      interval: 60_000,
      bucket: "notification-writes",
      methods: ["POST", "DELETE"]
    )
  end

  pipeline :search_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 120, interval: 60_000, bucket: "search")
  end

  pipeline :platform_write_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "platform-writes",
      methods: ["POST", "PATCH", "DELETE"]
    )
  end

  pipeline :admin_only do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin])
  end

  pipeline :member_or_admin do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :member])
  end

  pipeline :athlete_or_admin do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :coach, :athlete])
  end

  pipeline :tenant_member do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)

    plug(MilosTrainingWeb.Plugs.RequireTenantRole,
      roles: [:owner, :admin, :coach, :athlete, :member]
    )
  end

  pipeline :user_only do
    plug(MilosTrainingWeb.Plugs.AssignUserContext)
  end

  pipeline :tenant_context do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
  end

  pipeline :organization_admin do
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin])
  end

  pipeline :vendor do
    plug(MilosTrainingWeb.Plugs.RequireVendor)
  end

  scope "/api" do
    pipe_through(:api)

    get("/health", MilosTrainingWeb.HealthController, :index)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
    get("/calendar/feed.ics", MilosTrainingWeb.CalendarFeedController, :feed)
    get("/theme", MilosTrainingWeb.ThemeController, :show)
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through([:api, :auth_rate_limited])

    get("/nickname-available", AuthController, :nickname_available)
    post("/register", AuthController, :register)
    post("/register-member", AuthController, :register_member)
    post("/register-admin", AuthController, :register_admin)
    post("/invitations/inspect", OrganizationAccessController, :inspect)
    post("/login", AuthController, :login)
    post("/refresh", AuthController, :refresh)
    post("/logout", AuthController, :logout)
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited])

    get("/me", AuthController, :me)
    post("/sign-out-all", AuthController, :sign_out_all)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited])

    get("/memberships", OrganizationAccessController, :memberships)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :invitation_rate_limited])

    post("/memberships/redeem", OrganizationAccessController, :redeem)
  end

  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_context,
      :organization_admin,
      :tenant_write_rate_limited
    ])

    post("/invitations", OrganizationAccessController, :issue)
    delete("/invitations/:id", OrganizationAccessController, :revoke)
  end

  scope "/api/org/:organization_slug/me", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :messaging_rate_limited,
      :search_rate_limited
    ])

    get("/finance", MyFinanceController, :index)
    get("/entitlement", MyFinanceController, :entitlement)
    get("/invoices/:id/download-url", MyFinanceController, :invoice_download_url)
    get("/reviews", ReviewController, :index)
    post("/reviews", ReviewController, :create)
    get("/search/users", MeController, :search_users)

    get("/threads/unread-count", MessagingController, :unread_count)
    post("/threads", MessagingController, :create_thread)
    get("/threads", MessagingController, :list_threads)
    get("/threads/:id", MessagingController, :show_thread)
    get("/threads/:id/messages", MessagingController, :list_messages)
    post("/threads/:id/messages", MessagingController, :send_message)
    post("/threads/:id/read", MessagingController, :mark_read)
  end

  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :member_or_admin,
      :tenant_write_rate_limited
    ])

    get("/schedule", ScheduleController, :index)
    get("/landing", LandingController, :show)
    post("/bookings", ScheduleController, :create_booking)
    delete("/bookings/:id", ScheduleController, :delete_booking)
    get("/workouts/:id", WorkoutController, :show)
    get("/workouts/:id/scales", WorkoutController, :scales)
  end

  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :athlete_or_admin,
      :tenant_write_rate_limited
    ])

    get("/my-workouts", MyWorkoutController, :index)
    post("/my-workouts/requests", MyWorkoutController, :request_assignment)
    patch("/my-workouts/assignments/:id/reject", MyWorkoutController, :reject)
    patch("/my-workouts/assignments/:id/reschedule", MyWorkoutController, :reschedule)
  end

  scope "/api/org/:organization_slug/admin", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :admin_only,
      :tenant_write_rate_limited,
      :upload_rate_limited,
      :search_rate_limited
    ])

    get("/users", AdminUserController, :index)
    get("/users/:id", AdminUserController, :show)
    get("/users/:id/finance", AdminUserController, :finance)
    get("/users/:id/training-history", AdminUserController, :training_history)
    get("/users/:id/schedule", AdminUserController, :schedule)
    post("/users/:id/programming", AdminUserController, :program_workout)
    get("/users/:id/prs", AdminUserController, :prs)
    get("/users/:id/incidents", AdminUserController, :incidents)
    get("/users/:id/messages", AdminUserController, :messages)
    get("/users/:id/coaching-context", AdminUserController, :coaching_context)
    post("/users/:id/allowance-extensions", AdminUserController, :grant_allowance)
    delete("/users/:id", AdminUserController, :delete)

    post(
      "/users/:id/allowance-extensions/:entry_id/revoke",
      AdminUserController,
      :revoke_allowance
    )

    patch("/users/:id/role", AdminUserController, :update_role)
    get("/search", AdminSearchController, :index)
    get("/analytics/summary", AdminAnalyticsController, :summary)
    get("/athletes", AdminUserController, :index_athletes)
    get("/scale-levels", AdminScaleLevelController, :index)
    put("/scale-levels", AdminScaleLevelController, :update)
    get("/class-types", AdminClassTypeController, :index)
    post("/class-types", AdminClassTypeController, :create)
    patch("/class-types/:id", AdminClassTypeController, :update)
    delete("/class-types/:id", AdminClassTypeController, :delete)
    get("/workouts", AdminWorkoutController, :index)
    get("/workout-folders", AdminWorkoutFolderController, :index)
    post("/workout-folders", AdminWorkoutFolderController, :create)
    patch("/workout-folders/:id", AdminWorkoutFolderController, :update)
    delete("/workout-folders/:id", AdminWorkoutFolderController, :delete)
    post("/workouts", AdminWorkoutController, :create)
    post("/workouts/dsl/parse", AdminWorkoutDslController, :parse)
    get("/workouts/dsl/manual", AdminWorkoutDslController, :manual)
    get("/workouts/:id/dsl", AdminWorkoutDslController, :show_authoring)
    post("/workouts/:id/dsl/publish", AdminWorkoutDslController, :publish)
    get("/workouts/:id", AdminWorkoutController, :show)
    patch("/workouts/:id/draft", AdminWorkoutController, :update_draft)
    patch("/workouts/:id/library", AdminWorkoutController, :update_library)
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
    post("/schedule/slots/series", AdminScheduleController, :create_series)
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
    get("/finance/cleanup-records", AdminFinanceController, :cleanup_records)
    post("/finance/cleanup-records/:id/purge", AdminFinanceController, :purge_record)
    get("/finance/packages", AdminFinanceController, :packages)
    post("/finance/packages", AdminFinanceController, :create_package)
    get("/finance/packages/:id", AdminFinanceController, :package)
    patch("/finance/packages/:id", AdminFinanceController, :update_package)
    patch("/finance/packages/:id/retire", AdminFinanceController, :retire_package)
    post("/finance/entitlements/backfill", AdminFinanceController, :backfill_entitlements)
    get("/finance/members", AdminFinanceController, :members)
    get("/finance/members/:id", AdminFinanceController, :member)
    patch("/finance/members/:id", AdminFinanceController, :update_member)
    post("/finance/members/:id/packages", AdminFinanceController, :assign_package)
    post("/finance/members/:id/payments", AdminFinanceController, :record_payment)
    post("/finance/members/:id/receipts", AdminFinanceController, :create_receipt)
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

    post(
      "/finance/invoices/:id/upload-complete",
      AdminFinanceController,
      :invoice_upload_complete
    )

    get("/finance/invoices/:id/download-url", AdminFinanceController, :invoice_download_url)

    post("/finance/members/:id/promotion-redemptions", AdminFinanceController, :redeem_promotion)
    get("/finance/promotions", AdminFinanceController, :promotions)
    post("/finance/promotions", AdminFinanceController, :create_promotion)
    get("/finance/promotions/:id/codes", AdminFinanceController, :promotion_codes)
    post("/finance/promotions/:id/codes", AdminFinanceController, :create_promotion_code)
    get("/finance/referral-programs", AdminFinanceController, :referral_programs)
    post("/finance/referral-programs", AdminFinanceController, :create_referral_program)
    patch("/finance/referral-programs/:id", AdminFinanceController, :update_referral_program)
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

  scope "/api/platform", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :vendor,
      :platform_write_rate_limited
    ])

    get("/organizations", PlatformOrganizationController, :index)
    post("/organizations", PlatformOrganizationController, :create)
    delete("/organizations/:id", PlatformOrganizationController, :delete)
    get("/organizations/:id/access", PlatformOrganizationController, :access)
    post("/organizations/:id/invitations", PlatformOrganizationController, :invite)

    patch(
      "/organizations/:id/memberships/:membership_id/role",
      PlatformOrganizationController,
      :membership_role
    )

    patch("/organizations/:id/lifecycle", PlatformOrganizationController, :lifecycle)
    patch("/organizations/:id/settings", PlatformOrganizationController, :settings)
  end

  scope "/api/me", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :upload_rate_limited,
      :search_rate_limited
    ])

    patch("/profile", MeController, :update_profile)
    post("/avatar/upload-url", MeController, :avatar_upload_url)
    patch("/avatar", MeController, :update_avatar)
    get("/search/users", MeController, :search_users)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :notification_write_rate_limited,
      :tenant_write_rate_limited
    ])

    get("/calendar/export-links", CalendarFeedController, :links)
    post("/calendar/export-links/regenerate", CalendarFeedController, :regenerate_links)
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
    get("/wellbeing/injuries", WellbeingController, :index)
    post("/wellbeing/injuries", WellbeingController, :create)
    patch("/wellbeing/injuries/:id/heal", WellbeingController, :heal)
    get("/challenges/:id/leaderboard", ChallengeController, :leaderboard)
    post("/challenges/:id/opt_in", ChallengeController, :opt_in)
    delete("/challenges/:id/opt_in", ChallengeController, :opt_out)
  end

  scope "/api/workouts", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited, :user_only])

    get("/:id/timer-sequence", ExecutionController, :timer_sequence)
  end

  scope "/api/executions", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :execution_rate_limited
    ])

    get("/", ExecutionController, :index)
    post("/", ExecutionController, :create)
    get("/:id", ExecutionController, :show)
    patch("/:id/progress", ExecutionController, :update_progress)
    post("/:id/notes", ExecutionController, :submit_note)
    patch("/:id/complete", ExecutionController, :complete)
    post("/:id/modifications", ExecutionController, :add_modifications)
  end

  scope "/api/gamification", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited
    ])

    get("/preferences", GamificationPreferencesController, :show)
    put("/preferences", GamificationPreferencesController, :update)
  end

  scope "/api/prs", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited
    ])

    get("/", PRController, :index)
    post("/", PRController, :create)
    patch("/:id/edit", PRController, :edit)
    patch("/:id", PRController, :update)
    delete("/:id", PRController, :delete)
    get("/:id/history", PRController, :history)
    post("/:id/share", PRController, :share)
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
