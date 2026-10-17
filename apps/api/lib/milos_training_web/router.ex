defmodule MilosTrainingWeb.Router do
  use MilosTrainingWeb, :router

  @all_roles MilosTraining.Organizations.Domain.MembershipPolicy.roles()

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

  pipeline :execution_interaction_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "execution-interactions",
      methods: ["POST"]
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

  # ADR-132: exact-nickname grantee lookup; a tight budget bounds guessing.
  pipeline :grantee_lookup_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "pr-grantee-lookup")
  end

  pipeline :slug_alias_rate_limited do
    # Called by the web proxy (one client address for every browser) and
    # cached there, so the budget is generous; it only bounds enumeration.
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 600,
      interval: 60_000,
      bucket: "organization-slug-aliases"
    )
  end

  pipeline :platform_write_rate_limited do
    plug(MilosTrainingWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "platform-writes",
      methods: ["POST", "PATCH", "DELETE"]
    )
  end

  # Staff routes need the capability RouteCapabilities lists for the action
  # (ADR-099); data scope is enforced by the application services.
  pipeline :admin_only do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireRouteCapability)
  end

  pipeline :tenant_staff do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :coach])
  end

  # Members and staff; athletes have their own programming instead.
  pipeline :member_or_admin do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: @all_roles -- [:athlete])
  end

  pipeline :athlete_or_admin do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :coach, :athlete])
  end

  pipeline :staff_only do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireRouteCapability)
  end

  pipeline :tenant_member do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
    plug(MilosTrainingWeb.Plugs.RequireTenantRole, roles: @all_roles)
  end

  pipeline :user_only do
    plug(MilosTrainingWeb.Plugs.AssignUserContext)
  end

  pipeline :tenant_context do
    plug(MilosTrainingWeb.Plugs.ResolveTenantContext)
  end

  pipeline :organization_admin do
    plug(MilosTrainingWeb.Plugs.RequireRouteCapability)
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

  # ADR-122: unauthenticated retired-slug lookup behind the web proxy's 308.
  scope "/api" do
    pipe_through([:api, :slug_alias_rate_limited])

    get(
      "/organization-slug-aliases/:slug",
      MilosTrainingWeb.OrganizationSlugAliasController,
      :show
    )
  end

  scope "/api/auth", MilosTrainingWeb do
    pipe_through([:api, :auth_rate_limited])

    get("/nickname-available", AuthController, :nickname_available)
    post("/register", AuthController, :register)
    post("/register-member", AuthController, :register_member)
    post("/register-admin", AuthController, :register_admin)
    post("/invitations/inspect", OrganizationAccessController, :inspect)
    get("/join/:slug", OrganizationAccessController, :inspect_join_link)
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
    post("/organizations", OwnerOrganizationController, :create)
  end

  scope "/api", MilosTrainingWeb do
    pipe_through([:api, :authenticated, :invitation_rate_limited])

    post("/memberships/redeem", OrganizationAccessController, :redeem)
    post("/memberships/join/:slug", OrganizationAccessController, :join)
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

    get("/invitations", OrganizationAccessController, :list_invitations)
    post("/invitations", OrganizationAccessController, :issue)
    get("/join-link", OrganizationAccessController, :show_join_link)
    put("/join-link", OrganizationAccessController, :update_join_link)
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
    get("/videos", MyContentController, :videos)
    get("/form-reviews", CoachingExtrasController, :my_form_reviews)
    post("/form-reviews", CoachingExtrasController, :submit_form_review)
    post("/form-reviews/:id/withdraw", CoachingExtrasController, :withdraw_form_review)
    get("/nutrition-plan", CoachingExtrasController, :my_nutrition_plan)
    get("/corporate-enrollment", PaymentModelsController, :enrollment_offer)
    post("/corporate-enrollment", PaymentModelsController, :enroll)
    get("/appointments/slots", AppointmentsController, :offered_slots)
    get("/appointments", AppointmentsController, :my_appointments)
    post("/appointments", AppointmentsController, :book)
    post("/appointments/:id/cancel", AppointmentsController, :cancel)
    get("/progress", MyContentController, :progress)
    get("/history", TrainingHistoryController, :mine)
    get("/invoices/:id/download-url", MyFinanceController, :invoice_download_url)
    get("/refund-receipts", MyFinanceController, :refund_receipts)
    get("/refund-receipts/:id", MyFinanceController, :refund_receipt)
    get("/refund-receipts/:id/document", MyFinanceController, :refund_receipt_document)
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

  # ADR-138: a member's choices about their gym's club and its channels.
  scope "/api/org/:organization_slug/community", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/wod-today", CommunityController, :wod_today)
    put("/clubs/:id/notify-level", CommunityController, :set_notify_level)
    post("/channels/:id/membership", CommunityController, :join_channel)
    delete("/channels/:id/membership", CommunityController, :leave_channel)
    post("/posts", CommunityPostController, :create)
    delete("/posts/:id", CommunityPostController, :delete)
    put("/posts/:id/hidden", CommunityPostController, :hide)
    put("/posts/:id/pinned", CommunityPostController, :pin)
    put("/posts/:id/kudos", CommunityPostController, :kudos)
    get("/posts/:id/comments", CommunityPostController, :comments)
    post("/posts/:id/comments", CommunityPostController, :comment)
    delete("/comments/:id", CommunityPostController, :delete_comment)
  end

  # ADR-118: standalone training log (class / offline workouts).
  scope "/api/org/:organization_slug/me/training-log", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/entries", TrainingLogController, :index)
    post("/entries", TrainingLogController, :create)
    get("/entries/:id", TrainingLogController, :show)
    patch("/entries/:id", TrainingLogController, :update)
    post("/entries/:id/void", TrainingLogController, :void)
    get("/sources", TrainingLogController, :sources)
  end

  # ADR-124: the acting user's own injury safety warnings for a workout they
  # are about to start (athletes and members alike).
  scope "/api/org/:organization_slug/me/workouts/:workout_id", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/injury-warnings", MyInjuryWarningController, :show)
    post("/injury-warnings/acknowledge", MyInjuryWarningController, :acknowledge)
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
    post("/landing/leaderboard-opt-in", LandingController, :update_leaderboard_preference)
    post("/bookings", ScheduleController, :create_booking)
    post("/bookings/waitlist", ScheduleController, :join_waitlist)
    post("/bookings/guests", ScheduleController, :create_guest_booking)
    delete("/bookings/:id", ScheduleController, :delete_booking)
    post("/bookings/:id/check-in", ScheduleController, :check_in_class)
    get("/locations", ScheduleController, :locations)
    post("/check-ins", ScheduleController, :check_in)
    get("/workouts/:id", WorkoutController, :show)
    get("/workouts/:id/scales", WorkoutController, :scales)
  end

  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/class-timers/:slot_id", ClassTimerController, :show)
    post("/class-timers/:slot_id/commands", ClassTimerController, :command)
    # TD-092: challenges are tenant rows; these run in the gym's scope.
    get("/challenges/:id/leaderboard", ChallengeController, :leaderboard)
    post("/challenges/:id/opt_in", ChallengeController, :opt_in)
    delete("/challenges/:id/opt_in", ChallengeController, :opt_out)
  end

  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :athlete_or_admin,
      :tenant_write_rate_limited
    ])

    post("/my-workouts/requests", MyWorkoutController, :request_assignment)
    patch("/my-workouts/assignments/:id/reschedule", MyWorkoutController, :reschedule)
  end

  # ADR-125: members receive personal assignments and class variants too, so
  # listing, opening and rejecting assignments is open to every tenant role
  # (the services only ever act on the caller's own assignment links).
  scope "/api/org/:organization_slug", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/my-workouts", MyWorkoutController, :index)
    post("/my-workouts/assignments/:id/open", MyWorkoutController, :open)
    patch("/my-workouts/assignments/:id/reject", MyWorkoutController, :reject)
  end

  # ADR-129: members' PRs are readable by the gym's coaches, so the dossier PR
  # tab admits coaches as well as owners/admins. Owners/admins who are not
  # coaches get a role-safe empty state; the database enforces the rest.
  scope "/api/org/:organization_slug/admin", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_staff
    ])

    get("/users/:id/prs", AdminUserController, :prs)
    # ADR-132: how a coach finds those members (client scope does not narrow it).
    get("/pr-members", AdminUserController, :pr_members)
  end

  # Staff work that coaches share with owners and admins (ADR-098).
  scope "/api/org/:organization_slug/staff", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :staff_only,
      :tenant_write_rate_limited
    ])

    get("/members", StaffController, :index)
    get("/clients/:user_id/coach-notes", CoachNotesController, :index)
    get("/clients/:user_id/journal", JournalController, :client_journal)
    post("/clients/:user_id/coach-notes", CoachNotesController, :create)
    patch("/coach-notes/:id", CoachNotesController, :update)
    delete("/coach-notes/:id", CoachNotesController, :delete)
    get("/coach-notes/reads", CoachNotesController, :reads)
    put("/me/notes-visibility", CoachNotesController, :visibility)
    get("/cleaning/areas", CleaningController, :areas)
    post("/cleaning/areas", CleaningController, :create_area)
    patch("/cleaning/areas/:id", CleaningController, :update_area)
    post("/cleaning/areas/:id/archive", CleaningController, :archive_area)
    get("/cleaning/entries", CleaningController, :entries)
    post("/cleaning/entries", CleaningController, :start)
    post("/cleaning/entries/:id/finish", CleaningController, :finish)
    get("/inventory/machines", InventoryController, :machines)
    post("/inventory/machines", InventoryController, :create_machine)
    patch("/inventory/machines/:id", InventoryController, :update_machine)
    post("/inventory/machines/:id/archive", InventoryController, :archive_machine)
    get("/inventory/machines/:id/events", InventoryController, :machine_events)
    post("/inventory/machines/:id/events", InventoryController, :log_machine_event)
    get("/inventory/supplies", InventoryController, :supplies)
    post("/inventory/supplies", InventoryController, :create_supply)
    patch("/inventory/supplies/:id", InventoryController, :update_supply)
    post("/inventory/supplies/:id/archive", InventoryController, :archive_supply)
    get("/inventory/supplies/:id/low-reports", InventoryController, :supply_reports)
    post("/inventory/supplies/:id/low-reports", InventoryController, :report_low)
    get("/inventory/supplies/:id/movements", InventoryController, :movements)
    post("/inventory/supplies/:id/movements", InventoryController, :record_movement)
    get("/inventory/report", InventoryController, :report)
    get("/coaching-relationships", CoachingRelationshipsController, :index)
    post("/coaching-relationships", CoachingRelationshipsController, :create)
    post("/coaching-relationships/:id/end", CoachingRelationshipsController, :finish)
    get("/form-reviews", CoachingExtrasController, :form_review_queue)
    post("/form-reviews/:id/review", CoachingExtrasController, :complete_form_review)
    get("/reply-queue", CoachingExtrasController, :reply_queue)
    get("/my-client-stats", CoachingExtrasController, :my_client_stats)
    get("/clients/:user_id/nutrition-plan", CoachingExtrasController, :nutrition_plan)
    put("/clients/:user_id/nutrition-plan", CoachingExtrasController, :save_nutrition_plan)
    get("/appointment-slots", AppointmentsController, :slots)
    post("/appointment-slots", AppointmentsController, :create_slot)
    post("/appointment-slots/:id/cancel", AppointmentsController, :cancel_slot)
    post("/appointment-slots/:id/bookings", AppointmentsController, :book_for_client)
    post("/appointments/:id/attendance", AppointmentsController, :attendance)
    post("/appointments/:id/cancel", AppointmentsController, :cancel)
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
    get("/users/:id/history", TrainingHistoryController, :for_user)
    get("/users/:id/schedule", AdminUserController, :schedule)
    post("/users/:id/programming", AdminUserController, :program_workout)
    post("/users/:id/class-placement", AdminUserController, :place_in_class)
    get("/users/:id/incidents", AdminUserController, :incidents)
    get("/users/:id/messages", AdminUserController, :messages)
    get("/users/:id/coaching-context", AdminUserController, :coaching_context)
    post("/users/:id/allowance-extensions", AdminUserController, :grant_allowance)
    get("/users/:id/freezes", AdminUserController, :freezes)
    post("/users/:id/freezes", AdminUserController, :create_freeze)
    post("/users/:id/freezes/:freeze_id/cancel", AdminUserController, :cancel_freeze)
    delete("/users/:id", AdminUserController, :delete)

    post(
      "/users/:id/allowance-extensions/:entry_id/revoke",
      AdminUserController,
      :revoke_allowance
    )

    patch("/users/:id/role", AdminUserController, :update_role)
    put("/users/:id/roles", AdminUserController, :update_roles)
    get("/role-access", RoleAccessController, :show)
    put("/role-access/:role", RoleAccessController, :update)
    post("/organization/transfer", OwnerOrganizationController, :transfer)
    post("/organization/archive", OwnerOrganizationController, :archive)
    patch("/users/:id/coach-scope", AdminUserController, :update_coach_scope)
    get("/users/:id/membership-status", AdminUserController, :membership_status)
    get("/search", AdminSearchController, :index)
    get("/analytics/summary", AdminAnalyticsController, :summary)
    get("/athletes", AdminUserController, :index_athletes)
    get("/scale-levels", AdminScaleLevelController, :index)
    put("/scale-levels", AdminScaleLevelController, :update)
    get("/class-types", AdminClassTypeController, :index)
    get("/videos", AdminContentController, :index)
    post("/videos", AdminContentController, :create)
    patch("/videos/:id", AdminContentController, :update)
    post("/videos/:id/publish", AdminContentController, :publish)
    post("/videos/:id/archive", AdminContentController, :archive)
    get("/locations", AdminFacilityController, :index_locations)
    post("/locations", AdminFacilityController, :create_location)
    patch("/locations/:id", AdminFacilityController, :update_location)
    post("/locations/:id/archive", AdminFacilityController, :archive_location)
    get("/check-ins", AdminFacilityController, :index_check_ins)
    post("/check-ins", AdminFacilityController, :create_check_in)
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
    post("/workouts/timer-preview", AdminWorkoutTimerPreviewController, :create)
    post("/workouts/free-text/analyze", AdminWorkoutFreeTextController, :analyze)
    get("/workouts/dsl/manual", AdminWorkoutDslController, :manual)
    get("/workouts/:id/dsl", AdminWorkoutDslController, :show_authoring)
    post("/workouts/:id/dsl/publish", AdminWorkoutDslController, :publish)
    get("/workouts/:id", AdminWorkoutController, :show)
    patch("/workouts/:id/draft", AdminWorkoutController, :update_draft)
    patch("/workouts/:id/library", AdminWorkoutController, :update_library)
    post("/workouts/:id/publish", AdminWorkoutController, :publish)
    post("/workouts/:id/reopen", AdminWorkoutController, :reopen)
    post("/workouts/:id/duplicate", AdminWorkoutController, :duplicate)
    post("/workouts/:id/copy", AdminWorkoutController, :copy)
    patch("/workouts/:id/icon", AdminWorkoutController, :update_icon)
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
    get("/onboarding", AdminOnboardingController, :show)
    patch("/onboarding", AdminOnboardingController, :update)
    patch("/settings", AdminSettingsController, :update)
    get("/branding", AdminBrandingController, :show)
    get("/public-profile", AdminPublicProfileController, :show)
    put("/public-profile", AdminPublicProfileController, :update)
    post("/public-profile/photos", AdminPublicProfileController, :photo_upload)
    post("/public-profile/photos/:id/complete", AdminPublicProfileController, :complete_photo)
    post("/branding/logo/upload-url", AdminBrandingController, :logo_upload_url)
    put("/branding/logo", AdminBrandingController, :finalize_logo)
    delete("/branding/logo", AdminBrandingController, :remove_logo)
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
    get("/finance/package-catalog", AdminFinanceController, :package_catalog)
    get("/finance/subscriptions/:id/beneficiaries", PaymentModelsController, :beneficiaries)
    post("/finance/subscriptions/:id/beneficiaries", PaymentModelsController, :add_beneficiary)

    post(
      "/finance/subscriptions/:id/beneficiaries/:beneficiary_id/remove",
      PaymentModelsController,
      :remove_beneficiary
    )

    get("/finance/corporate-clients", PaymentModelsController, :clients)
    post("/finance/corporate-clients", PaymentModelsController, :create_client)
    patch("/finance/corporate-clients/:id", PaymentModelsController, :update_client)
    get("/finance/corporate-clients/:id/seats", PaymentModelsController, :seats)
    post("/finance/corporate-clients/:id/seats", PaymentModelsController, :add_seat)

    post(
      "/finance/corporate-clients/:id/seats/:subscription_id/end",
      PaymentModelsController,
      :end_seat
    )

    get("/finance/corporate-clients/:id/invoices", PaymentModelsController, :invoices)
    post("/finance/corporate-clients/:id/invoices", PaymentModelsController, :create_invoice)
    post("/finance/corporate-invoices/:id/status", PaymentModelsController, :invoice_status)
    get("/finance/corporate-invoices/:id", PaymentModelsController, :invoice)
    post("/finance/corporate-invoices/:id/payments", PaymentModelsController, :record_payment)

    post(
      "/finance/corporate-invoices/:id/payments/:payment_id/reverse",
      PaymentModelsController,
      :reverse_payment
    )

    post("/finance/corporate-invoices/:id/send", PaymentModelsController, :send_invoice)
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

    # ADR-126 refund receipts, provider reconciliation and accounting exports.
    get("/finance/refund-receipts", AdminFinanceAccountingController, :refund_receipts)
    get("/finance/refund-receipts/:id", AdminFinanceAccountingController, :refund_receipt)

    get(
      "/finance/refund-receipts/:id/document",
      AdminFinanceAccountingController,
      :refund_receipt_document
    )

    get(
      "/finance/reconciliation-records",
      AdminFinanceAccountingController,
      :reconciliation_records
    )

    post(
      "/finance/reconciliation-records",
      AdminFinanceAccountingController,
      :record_reconciliation_line
    )

    get(
      "/finance/reconciliation-records/:id/candidates",
      AdminFinanceAccountingController,
      :reconciliation_candidates
    )

    post(
      "/finance/reconciliation-records/:id/match",
      AdminFinanceAccountingController,
      :match_reconciliation
    )

    post(
      "/finance/reconciliation-records/:id/unmatch",
      AdminFinanceAccountingController,
      :unmatch_reconciliation
    )

    get("/finance/accounting-exports", AdminFinanceAccountingController, :exports)
    post("/finance/accounting-exports", AdminFinanceAccountingController, :request_export)

    get(
      "/finance/accounting-exports/:id/download",
      AdminFinanceAccountingController,
      :export_download
    )

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
    patch("/wellbeing/injuries/:id", AdminWellbeingController, :update)
    post("/wellbeing/injuries/:id/reopen", AdminWellbeingController, :reopen)
    # ADR-124 injury-aware workout safety warnings (informational only).
    post("/wellbeing/injury-warnings", AdminInjuryWarningController, :evaluate)
    post("/wellbeing/injury-warnings/acknowledge", AdminInjuryWarningController, :acknowledge)
    get("/schedule/slots/:id/injury-warnings", AdminInjuryWarningController, :slot)
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

    post(
      "/organizations/:id/invitations/email",
      PlatformOrganizationController,
      :invitation_email
    )

    patch(
      "/organizations/:id/memberships/:membership_id/role",
      PlatformOrganizationController,
      :membership_role
    )

    patch("/organizations/:id/lifecycle", PlatformOrganizationController, :lifecycle)
    patch("/organizations/:id/name", PlatformOrganizationController, :rename)
    # ADR-122 slug rename with typed confirmation and retired-slug aliases.
    get("/organizations/:id/slug-impact", PlatformOrganizationController, :slug_impact)
    patch("/organizations/:id/slug", PlatformOrganizationController, :rename_slug)
    patch("/organizations/:id/settings", PlatformOrganizationController, :settings)

    post(
      "/organizations/:id/branding/logo/upload-url",
      PlatformOrganizationBrandingController,
      :logo_upload_url
    )

    put(
      "/organizations/:id/branding/logo",
      PlatformOrganizationBrandingController,
      :finalize_logo
    )

    delete(
      "/organizations/:id/branding/logo",
      PlatformOrganizationBrandingController,
      :remove_logo
    )

    # ADR-117 reviewed tenant export/purge workflow.
    get("/organization-purges", PlatformOrganizationPurgeController, :index)
    post("/organizations/:id/purge", PlatformOrganizationPurgeController, :create)
    get("/organizations/:id/purge", PlatformOrganizationPurgeController, :show)
    post("/organizations/:id/purge/approve", PlatformOrganizationPurgeController, :approve)
    post("/organizations/:id/purge/cancel", PlatformOrganizationPurgeController, :cancel)
    post("/organizations/:id/purge/resume", PlatformOrganizationPurgeController, :resume)
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
    post("/tours/:audience/complete", MeController, :complete_tour)
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
    patch("/wellbeing/injuries/:id", WellbeingController, :update)
    post("/wellbeing/injuries/:id/reopen", WellbeingController, :reopen)
    get("/wellbeing/check-ins", CheckInController, :index)
    post("/wellbeing/check-ins", CheckInController, :create)
    delete("/wellbeing/check-ins/:id", CheckInController, :delete)
    post("/journal/comments/batch", JournalCommentController, :batch)
    put("/journal/comments/:id", JournalCommentController, :save)
    delete("/journal/comments/:id", JournalCommentController, :delete)
    get("/me/journal", JournalController, :index)
    put("/me/journal/entries/:kind/:id/visibility", JournalController, :set_visibility)
    post("/me/journal/notes", JournalController, :create_note)
    patch("/me/journal/notes/:id", JournalController, :update_note)
    delete("/me/journal/notes/:id", JournalController, :delete_note)
    get("/me/clubs", CommunityController, :my_clubs)
    get("/me/feed", CommunityPostController, :feed)
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
    get("/vault", ExecutionController, :vault)
    get("/:id", ExecutionController, :show)
    patch("/:id/progress", ExecutionController, :update_progress)
    patch("/:id/complete", ExecutionController, :complete)
  end

  # ADR-123: batched client interaction analytics get their own bucket so a
  # chatty client can never eat into the progress/complete budget above.
  scope "/api/executions", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :execution_interaction_rate_limited
    ])

    post("/:id/interactions", ExecutionController, :record_interactions)
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

  # ADR-129: personal PR sharing (global, not tenant-scoped).
  scope "/api/pr-sharing", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited
    ])

    get("/", PRSharingController, :show)
    put("/coach-visibility", PRSharingController, :update_coach_visibility)
    post("/grants", PRSharingController, :create_grant)
    delete("/grants/:id", PRSharingController, :revoke_grant)
    get("/shared-with-me", PRSharingController, :shared_with_me)
  end

  scope "/api/pr-sharing", MilosTrainingWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :grantee_lookup_rate_limited
    ])

    get("/grantee-lookup", PRSharingController, :lookup_grantee)
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
