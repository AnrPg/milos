defmodule PaleeWeb.Router do
  use PaleeWeb, :router

  @all_roles Palee.Organizations.Domain.MembershipPolicy.roles()

  pipeline :api do
    plug(:accepts, ["json"])
    plug(OpenApiSpex.Plug.PutApiSpec, module: PaleeWeb.ApiSpec)
  end

  pipeline :authenticated do
    plug(Guardian.Plug.Pipeline,
      module: Palee.Infrastructure.Auth.Guardian,
      error_handler: PaleeWeb.AuthErrorHandler
    )

    plug(Guardian.Plug.VerifyHeader, scheme: "Bearer")
    plug(Guardian.Plug.EnsureAuthenticated)
    plug(Guardian.Plug.LoadResource)
    plug(PaleeWeb.Plugs.LoggerUserMetadata)
    plug(PaleeWeb.Plugs.AssignUserContext)
  end

  pipeline :auth_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 10, interval: 60_000)
  end

  pipeline :invitation_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 10, interval: 60_000)
  end

  pipeline :authenticated_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 600, interval: 60_000, bucket: "authenticated")
  end

  pipeline :tenant_write_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 120,
      interval: 60_000,
      bucket: "tenant-writes",
      methods: ["POST", "PATCH", "PUT", "DELETE"]
    )
  end

  pipeline :upload_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 20,
      interval: 300_000,
      bucket: "uploads",
      methods: ["POST"]
    )
  end

  # ADR-267: asking for "Download my data" is also capped per hour here, on
  # top of the service's one request in progress and one a day.
  pipeline :data_export_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 5,
      interval: 3_600_000,
      bucket: "data-exports",
      methods: ["POST"]
    )
  end

  # ADR-157: one upload per picked file, plus its completion.
  pipeline :media_upload_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 60,
      interval: 300_000,
      bucket: "media-uploads",
      methods: ["POST", "PATCH", "DELETE"]
    )
  end

  pipeline :ai_suggestion_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 20,
      interval: 300_000,
      bucket: "ai-suggestions",
      methods: ["POST"]
    )
  end

  pipeline :messaging_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "messaging",
      methods: ["POST"]
    )
  end

  # ADR-142: the public box page; the web server renders it, so many
  # visitors can arrive from one address.
  pipeline :public_box_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 600, interval: 60_000, bucket: "public-box")
  end

  pipeline :public_invite_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 60, interval: 60_000, bucket: "buddy-invite")
  end

  # ADR-156: invite pages; 32^8 codes behind a tight budget make guessing moot.
  pipeline :public_referral_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 120, interval: 60_000, bucket: "public-referral")
  end

  # ADR-191: a partner's counter opens a perk QR's link; the signed,
  # short-lived token makes guessing moot, the budget keeps scanners honest.
  pipeline :public_perk_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 60, interval: 60_000, bucket: "public-perk")
  end

  pipeline :execution_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 240,
      interval: 60_000,
      bucket: "execution",
      methods: ["POST", "PATCH"]
    )
  end

  pipeline :execution_interaction_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "execution-interactions",
      methods: ["POST"]
    )
  end

  pipeline :notification_write_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 120,
      interval: 60_000,
      bucket: "notification-writes",
      methods: ["POST", "DELETE"]
    )
  end

  # ADR-141: address lookups go to a shared OpenStreetMap geocoder.
  pipeline :geocode_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "geocode")
  end

  # ADR-185: new events from the member app («Διοργάνωση ως»).
  pipeline :event_create_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 10, interval: 3_600_000, bucket: "event-create")
  end

  # ADR-154: Γύρω μου searches run several indexed queries (and may geocode
  # a typed place); a generous budget that still bounds scraping.
  pipeline :around_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 120, interval: 60_000, bucket: "around")
  end

  # ADR-173: home-screen widgets, with their own token (not a session); a
  # widget refreshes every few minutes and on «+1 νερό».
  pipeline :widget do
    plug(PaleeWeb.Plugs.AuthenticateWidget)
    plug(PaleeWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "widget")
  end

  # ADR-253: box screens. Pairing has no sign-in, so a tight budget per
  # address bounds guessing codes; a paired screen polls with its own token.
  pipeline :box_screen_pairing do
    plug(PaleeWeb.Plugs.RateLimit, max: 10, interval: 60_000, bucket: "box-screen-pair")
  end

  pipeline :box_screen do
    plug(PaleeWeb.Plugs.AuthenticateBoxScreen)
    plug(PaleeWeb.Plugs.RateLimit, max: 120, interval: 60_000, bucket: "box-screen")
  end

  # Staff create screens and pairing codes (each POST makes a code).
  pipeline :box_screen_code_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 30,
      interval: 3_600_000,
      bucket: "box-screen-codes",
      methods: ["POST"]
    )
  end

  # ADR-155: door scans and the desk; generous for a busy door, bounded for guessing.
  pipeline :check_in_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 60, interval: 60_000, bucket: "check-in")
  end

  # ADR-155: Wallet downloads and Apple's PassKit web service (no app session;
  # many phones behind one address at a gym).
  pipeline :wallet_public do
    plug(OpenApiSpex.Plug.PutApiSpec, module: PaleeWeb.ApiSpec)
    plug(PaleeWeb.Plugs.RateLimit, max: 300, interval: 60_000, bucket: "wallet")
  end

  # ADR-161: Garmin's OAuth return (a browser redirect) and its push and
  # deregistration calls; no app session, Garmin may send in bursts.
  pipeline :garmin_public do
    plug(OpenApiSpex.Plug.PutApiSpec, module: PaleeWeb.ApiSpec)
    plug(PaleeWeb.Plugs.RateLimit, max: 600, interval: 60_000, bucket: "garmin-public")
  end

  # ADR-212: Brevo's transactional webhook (bursts after a big send) and the
  # one-click unsubscribe link of transactional email (mail apps POST it).
  pipeline :email_provider_webhook do
    plug(PaleeWeb.Plugs.RateLimit, max: 1200, interval: 60_000, bucket: "brevo-webhook")
    plug(PaleeWeb.Plugs.WebhookSecret, config_key: :brevo_webhook_secret)
  end

  pipeline :payment_provider_webhook do
    plug(PaleeWeb.Plugs.RateLimit, max: 600, interval: 60_000, bucket: "payment-webhook")
  end

  # ADR-261: the payment provider sends the owner back after connecting.
  pipeline :payment_connect_callback do
    plug(PaleeWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "payment-connect")
  end

  pipeline :email_unsubscribe do
    plug(PaleeWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "email-unsubscribe")
  end

  # ADR-161: connecting, syncing and confirming device imports.
  pipeline :device_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 30,
      interval: 60_000,
      bucket: "devices",
      methods: ["POST", "PATCH", "DELETE"]
    )
  end

  pipeline :search_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 120, interval: 60_000, bucket: "search")
  end

  # ADR-132: exact-nickname grantee lookup; a tight budget bounds guessing.
  pipeline :grantee_lookup_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit, max: 30, interval: 60_000, bucket: "pr-grantee-lookup")
  end

  pipeline :slug_alias_rate_limited do
    # Called by the web proxy (one client address for every browser) and
    # cached there, so the budget is generous; it only bounds enumeration.
    plug(PaleeWeb.Plugs.RateLimit,
      max: 600,
      interval: 60_000,
      bucket: "organization-slug-aliases"
    )
  end

  pipeline :platform_write_rate_limited do
    plug(PaleeWeb.Plugs.RateLimit,
      max: 60,
      interval: 60_000,
      bucket: "platform-writes",
      methods: ["POST", "PATCH", "DELETE"]
    )
  end

  # Staff routes need the capability RouteCapabilities lists for the action
  # (ADR-099); data scope is enforced by the application services.
  pipeline :admin_only do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireRouteCapability)
  end

  pipeline :tenant_staff do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :coach])
  end

  # Members and staff; athletes have their own programming instead.
  pipeline :member_or_admin do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireTenantRole, roles: @all_roles -- [:athlete])
  end

  pipeline :athlete_or_admin do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireTenantRole, roles: [:owner, :admin, :coach, :athlete])
  end

  pipeline :staff_only do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireRouteCapability)
  end

  pipeline :tenant_member do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
    plug(PaleeWeb.Plugs.RequireTenantRole, roles: @all_roles)
  end

  pipeline :user_only do
    plug(PaleeWeb.Plugs.AssignUserContext)
  end

  pipeline :tenant_context do
    plug(PaleeWeb.Plugs.ResolveTenantContext)
  end

  pipeline :organization_admin do
    plug(PaleeWeb.Plugs.RequireRouteCapability)
  end

  pipeline :vendor do
    plug(PaleeWeb.Plugs.RequireVendor)
  end

  scope "/api" do
    pipe_through(:api)

    get("/health", PaleeWeb.HealthController, :index)
    get("/openapi", OpenApiSpex.Plug.RenderSpec, [])
    get("/calendar/feed.ics", PaleeWeb.CalendarFeedController, :feed)
    get("/box-vocabulary", PaleeWeb.BoxVocabularyController, :show)
  end

  scope "/api/public/boxes", PaleeWeb do
    pipe_through([:api, :public_box_rate_limited])

    get("/:slug", PublicBoxController, :show)
    # ADR-248: the packages a box sells online.
    get("/:slug/packages", PublicBoxController, :packages)
  end

  # ADR-170: the public platform plan catalog (pricing, coach onboarding).
  scope "/api/public/platform-plans", PaleeWeb do
    pipe_through([:api, :public_box_rate_limited])

    get("/", PlatformPlanController, :index_public)
  end

  scope "/api/public/perk-verifications", PaleeWeb do
    pipe_through([:api, :public_perk_rate_limited])

    get("/:token", PerkVerificationController, :show)
    post("/:token/redeem", PerkVerificationController, :redeem)
  end

  scope "/api/public/referrals", PaleeWeb do
    pipe_through([:api, :public_referral_rate_limited])

    get("/:code", ReferralController, :invite)
  end

  # ADR-155: the .pkpass behind a signed, short-lived link (Safari opens it
  # without the app's bearer header), and Apple's PassKit web service.
  scope "/api/wallet", PaleeWeb do
    pipe_through([:wallet_public])

    get("/passes/:token", WalletController, :download)

    post(
      "/apple/v1/devices/:device_id/registrations/:pass_type_id/:serial",
      PassKitController,
      :register
    )

    delete(
      "/apple/v1/devices/:device_id/registrations/:pass_type_id/:serial",
      PassKitController,
      :unregister
    )

    get("/apple/v1/devices/:device_id/registrations/:pass_type_id", PassKitController, :serials)
    get("/apple/v1/passes/:pass_type_id/:serial", PassKitController, :latest)
    post("/apple/v1/log", PassKitController, :log)
  end

  scope "/api/integrations/garmin", PaleeWeb do
    pipe_through([:garmin_public])

    get("/callback", GarminIntegrationController, :callback)
    post("/push", GarminIntegrationController, :push)
    post("/deregistration", GarminIntegrationController, :deregistration)
  end

  # ADR-212: mail provider events and the unsubscribe link (no app session).
  scope "/api/webhooks", PaleeWeb do
    pipe_through([:email_provider_webhook])

    post("/brevo", BrevoWebhookController, :create)
  end

  # ADR-246: payment providers' webhooks (one URL per business account).
  scope "/api/webhooks/payments", PaleeWeb do
    pipe_through([:payment_provider_webhook])

    get("/:organization_id/:account_id", PaymentWebhookController, :show)
    post("/:organization_id/:account_id", PaymentWebhookController, :create)
  end

  scope "/api/payments/connect", PaleeWeb do
    pipe_through([:payment_connect_callback])

    get("/callback", PaymentConnectController, :callback)
  end

  # ADR-250: the Peppol access point's webhook (one secret URL per business).
  scope "/api/webhooks/peppol", PaleeWeb do
    pipe_through([:payment_provider_webhook])

    post("/:organization_id/:token", PeppolWebhookController, :create)
  end

  scope "/api/email/unsubscribe", PaleeWeb do
    pipe_through([:email_unsubscribe])

    get("/:token", EmailUnsubscribeController, :show)
    post("/:token", EmailUnsubscribeController, :create)
  end

  # ADR-122: unauthenticated retired-slug lookup behind the web proxy's 308.
  scope "/api" do
    pipe_through([:api, :slug_alias_rate_limited])

    get(
      "/organization-slug-aliases/:slug",
      PaleeWeb.OrganizationSlugAliasController,
      :show
    )
  end

  scope "/api/auth", PaleeWeb do
    pipe_through([:api, :auth_rate_limited])

    get("/nickname-available", AuthController, :nickname_available)
    get("/handle-available", AuthController, :handle_available)
    get("/handle-suggestion", AuthController, :handle_suggestion)
    post("/register", AuthController, :register)
    post("/register-member", AuthController, :register_member)
    post("/register-admin", AuthController, :register_admin)
    post("/invitations/inspect", OrganizationAccessController, :inspect)
    get("/join/:slug", OrganizationAccessController, :inspect_join_link)
    get("/join/:slug/athlete/:key", OrganizationAccessController, :inspect_athlete_join_link)
    post("/login", AuthController, :login)
    post("/refresh", AuthController, :refresh)
    post("/logout", AuthController, :logout)
    # ADR-187, ADR-206: password recovery (emailed link, handlers, codes).
    post("/password-reset-requests", PasswordRecoveryController, :request)
    post("/password-reset/inspect", PasswordRecoveryController, :inspect_link)
    post("/password-reset", PasswordRecoveryController, :complete)
    post("/password-reset/recovery-code", PasswordRecoveryController, :redeem_code)
    # ADR-213: the emailed link's page posts its token here.
    post("/verify-email", EmailVerificationController, :verify)
    # ADR-208: a security notice's emailed "sign out everywhere" link.
    post("/sign-out-everywhere", SecurityLinkController, :sign_out_everywhere)
    # ADR-207: the links of an email change (new address, then old address).
    post("/email-change/confirm", EmailChangeController, :confirm)
    post("/email-change/revert", EmailChangeController, :revert)
    # ADR-211: the emailed deletion links, and "undo" from the sign-in form.
    post("/account-deletion/confirm", AccountDeletionController, :confirm)
    post("/account-deletion/undo", AccountDeletionController, :undo)
    post("/account-deletion/undo-sign-in", AccountDeletionController, :undo_sign_in)
  end

  scope "/api/auth", PaleeWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited])

    get("/me", AuthController, :me)
    post("/sign-out-all", AuthController, :sign_out_all)
    # ADR-187: the login's up to three profiles.
    get("/profiles", AccountProfilesController, :index)
    post("/profiles", AccountProfilesController, :create)
    post("/switch-profile", AccountProfilesController, :switch)
    get("/recovery-codes", PasswordRecoveryController, :codes_status)
    post("/recovery-codes", PasswordRecoveryController, :generate_codes)
    # ADR-211: self-service deletion of the profile or the whole login.
    get("/account-deletion", AccountDeletionController, :show)
    delete("/account-deletion", AccountDeletionController, :delete)
    # ADR-213: a new verification link for the signed-in login.
    post("/verification-email", EmailVerificationController, :resend)
  end

  # ADR-211: asking takes the password, so a session gets few tries.
  scope "/api/auth", PaleeWeb do
    pipe_through([:api, :authenticated, :auth_rate_limited])

    post("/account-deletion", AccountDeletionController, :create)
  end

  # ADR-267: "Download my data" (GDPR articles 15 and 20).
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :data_export_rate_limited
    ])

    get("/me/data-exports", PersonalDataExportController, :index)
    post("/me/data-exports", PersonalDataExportController, :create)
  end

  # ADR-187: the password reset requests the signed-in person can handle
  # (vendor, box owner/admin/front desk, the person's coach).
  scope "/api/password-resets", PaleeWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited])

    get("/", PasswordRecoveryController, :inbox)
    post("/:id/claim", PasswordRecoveryController, :claim)
    post("/:id/release", PasswordRecoveryController, :release)
    post("/:id/link", PasswordRecoveryController, :issue_link)
    post("/:id/reject", PasswordRecoveryController, :reject)
    post("/:id/dismiss", PasswordRecoveryController, :dismiss)
    post("/:id/hide", PasswordRecoveryController, :hide)
  end

  scope "/api", PaleeWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited])

    get("/memberships", OrganizationAccessController, :memberships)
    post("/organizations", OwnerOrganizationController, :create)
    # ADR-170: an account opens its practice as an independent coach.
    post("/coach-practices", CoachPracticeController, :create)
    # ADR-163: the static, code-owned muscle taxonomy (ETag-cached).
    get("/anatomy/taxonomy", AnatomyController, :taxonomy)
  end

  scope "/api", PaleeWeb do
    pipe_through([:api, :authenticated, :invitation_rate_limited])

    post("/memberships/redeem", OrganizationAccessController, :redeem)
    post("/memberships/join/:slug", OrganizationAccessController, :join)
    post("/memberships/join/:slug/athlete/:key", OrganizationAccessController, :join_as_athlete)
    # ADR-204: same as redeem, plus the staff surface role and a new session.
    post("/auth/accept-invitation", AuthController, :accept_invitation)
  end

  scope "/api/org/:organization_slug", PaleeWeb do
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
    # ADR-209: invitations sent by email.
    post("/invitations/bulk", OrganizationAccessController, :bulk_invite)
    post("/invitations/:id/resend", OrganizationAccessController, :resend)
    get("/join-link", OrganizationAccessController, :show_join_link)
    put("/join-link", OrganizationAccessController, :update_join_link)
    delete("/invitations/:id", OrganizationAccessController, :revoke)
  end

  scope "/api/org/:organization_slug/me", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :messaging_rate_limited,
      :search_rate_limited
    ])

    get("/finance", MyFinanceController, :index)
    # ADR-246/247: paying invoices online and saved cards.
    get("/invoices/:id/payment-terms", MyPaymentsController, :terms)
    post("/invoices/:id/pay", MyPaymentsController, :pay)
    post("/payments/return", MyPaymentsController, :returned)
    post("/payments/sandbox/complete", MyPaymentsController, :sandbox_complete)
    get("/payments/:id", MyPaymentsController, :show)
    get("/payment-methods", MyPaymentsController, :methods)
    delete("/payment-methods/:id", MyPaymentsController, :revoke_method)
    put("/payment-methods/:id/autopay", MyPaymentsController, :set_autopay)
    # ADR-248: buying packages online, withdrawal, paying shop orders.
    get("/packages/:id/purchase-terms", MyPaymentsController, :package_terms)
    post("/packages/:id/buy", MyPaymentsController, :buy_package)
    post("/payments/:id/withdraw", MyPaymentsController, :withdraw)
    post("/shop/orders/:id/pay-online", MyPaymentsController, :pay_shop_order)
    # ADR-252: Box › Documents (sign, certificates, health certificate).
    get("/documents", MyDocumentsController, :index)
    get("/documents/signatures", MyDocumentsController, :signatures)
    get("/documents/signatures/:id/evidence", MyDocumentsController, :evidence)

    post(
      "/documents/health-certificate/uploads",
      MyDocumentsController,
      :request_health_upload
    )

    post("/documents/health-certificate", MyDocumentsController, :create_health_certificate)
    get("/documents/health-certificate/:id/file", MyDocumentsController, :health_file)

    delete(
      "/documents/health-certificate/:id",
      MyDocumentsController,
      :delete_health_certificate
    )

    get("/documents/:id", MyDocumentsController, :show)
    post("/documents/:id/sign", MyDocumentsController, :sign)
    # ADR-220: the member's renewal choice and leaving the box.
    put(
      "/membership/subscriptions/:id/auto-renew",
      MyMembershipController,
      :set_auto_renew
    )

    post("/membership/leave", MyMembershipController, :leave)
    delete("/membership/leave", MyMembershipController, :stay)
    # ADR-155: Box › Check-in.
    get("/check-in/code", MyCheckInController, :code)
    post("/check-in/code/reset", MyCheckInController, :reset_code)
    post("/wallet-passes", MyCheckInController, :add_wallet_pass)
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
    put("/home-location", HomeLocationController, :update_mine)
    # ADR-219: roles below my top role (an owner who also coaches).
    put("/roles", MyRolesController, :update)
    # ADR-167: Box › Συνδρομή › seasons.
    get("/seasons", SeasonController, :index)
    post("/seasons/:id/request", SeasonController, :request)
    post("/seasons/:id/cancel", SeasonController, :cancel)
    # ADR-156: «Φέρε φίλο».
    get("/referrals", ReferralController, :mine)
    post("/referrals/code", ReferralController, :rotate_code)
    # ADR-190: Box › Κατάστημα.
    get("/shop/storefront", MyShopController, :storefront)
    get("/shop/stock-alerts", MyShopController, :stock_alerts)
    put("/shop/variants/:id/stock-alert", MyShopController, :subscribe_stock_alert)
    delete("/shop/variants/:id/stock-alert", MyShopController, :unsubscribe_stock_alert)
    get("/shop/products", MyShopController, :products)
    get("/shop/products/:id", MyShopController, :product)
    post("/shop/cart/preview", MyShopController, :preview)
    post("/shop/orders", MyShopController, :place_order)
    get("/shop/orders", MyShopController, :orders)
    get("/shop/orders/:id", MyShopController, :order)
    post("/shop/orders/:id/pay", MyShopController, :pay)
    post("/shop/orders/:id/cancel", MyShopController, :cancel)
    get("/shop/transactions", MyShopController, :transactions)

    get("/threads/unread-count", MessagingController, :unread_count)
    post("/threads", MessagingController, :create_thread)
    get("/threads", MessagingController, :list_threads)
    get("/threads/:id", MessagingController, :show_thread)
    get("/threads/:id/messages", MessagingController, :list_messages)
    post("/threads/:id/messages", MessagingController, :send_message)
    post("/threads/:id/read", MessagingController, :mark_read)
  end

  # ADR-138: a member's choices about their gym's club and its channels.
  scope "/api/org/:organization_slug/community", PaleeWeb do
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
    put("/comments/:id/hidden", CommunityPostController, :hide_comment)
    # ADR-143: member groups.
    get("/groups", CommunityGroupController, :index)
    post("/groups", CommunityGroupController, :create)
    get("/groups/:id", CommunityGroupController, :show)
    patch("/groups/:id", CommunityGroupController, :update)
    post("/groups/:id/membership", CommunityGroupController, :join)
    delete("/groups/:id/membership", CommunityGroupController, :leave)
    put("/groups/:id/requests/:user_id", CommunityGroupController, :answer_request)
    put("/groups/:id/admins/:user_id", CommunityGroupController, :set_admin)
    delete("/groups/:id/members/:user_id", CommunityGroupController, :remove_member)
    post("/groups/:id/archive", CommunityGroupController, :archive)
    post("/groups/:id/reopen", CommunityGroupController, :reopen)
    # ADR-168: PT squads.
    get("/squads", PtSquadController, :index)
    post("/squads", PtSquadController, :create)
    get("/squads/:id", PtSquadController, :show)
    patch("/squads/:id", PtSquadController, :update)
    post("/squads/:id/invites", PtSquadController, :invite)
    put("/squads/:id/invite", PtSquadController, :answer)
    delete("/squads/:id/membership", PtSquadController, :leave)
    delete("/squads/:id/members/:user_id", PtSquadController, :remove_member)
    post("/squads/:id/archive", PtSquadController, :archive)
    post("/squads/:id/reopen", PtSquadController, :reopen)
  end

  # ADR-118: standalone training log (class / offline workouts).
  scope "/api/org/:organization_slug/me/training-log", PaleeWeb do
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
    # ADR-175: voice logging (a draft only; nothing is saved).
    get("/voice", MyVoiceLogController, :show)
    post("/voice/drafts", MyVoiceLogController, :create)
  end

  # ADR-124: the acting user's own injury safety warnings for a workout they
  # are about to start (athletes and members alike).
  scope "/api/org/:organization_slug/me/workouts/:workout_id", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/injury-warnings", MyInjuryWarningController, :show)
    post("/injury-warnings/acknowledge", MyInjuryWarningController, :acknowledge)
    # ADR-174: the coach-approved adaptation (never a pending suggestion).
    get("/scaling", MyScalingController, :show)
  end

  # ADR-163: WOD goals on the workout card and «τι ένιωσες» on the member's
  # own entries (athletes and members alike).
  scope "/api/org/:organization_slug", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/workouts/:id/goals", WorkoutGoalsController, :show)
    get("/me/goal-feedback/:entry_kind/:entry_id", GoalFeedbackController, :show)
    put("/me/goal-feedback/:entry_kind/:entry_id", GoalFeedbackController, :update)
    # ADR-164: the gym's exercises (and videos) for an atlas node.
    get("/anatomy/nodes/:node_id/exercises", AnatomyAtlasController, :exercises)
  end

  scope "/api/org/:organization_slug", PaleeWeb do
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

  scope "/api/org/:organization_slug", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :tenant_member,
      :tenant_write_rate_limited
    ])

    get("/class-timers/:slot_id", ClassTimerController, :show)
    post("/class-timers/:slot_id/commands", ClassTimerController, :command)

    # ADR-253 update 2026-10-29: «Στην οθόνη», the class's coach pins it on a box screen.
    get("/class-timers/:slot_id/screens", ClassScreenController, :index)

    put(
      "/class-timers/:slot_id/screens/:screen_id/override",
      ClassScreenController,
      :put_override
    )

    delete(
      "/class-timers/:slot_id/screens/:screen_id/override",
      ClassScreenController,
      :delete_override
    )

    # TD-092: challenges are tenant rows; these run in the gym's scope.
    get("/challenges/:id/leaderboard", ChallengeController, :leaderboard)
    post("/challenges/:id/opt_in", ChallengeController, :opt_in)
    delete("/challenges/:id/opt_in", ChallengeController, :opt_out)
  end

  scope "/api/org/:organization_slug", PaleeWeb do
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
  scope "/api/org/:organization_slug", PaleeWeb do
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
  scope "/api/org/:organization_slug/admin", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :admin_only,
      :geocode_rate_limited
    ])

    get("/geocode", AdminFacilityController, :search_addresses)
    get("/geocode/reverse", AdminFacilityController, :reverse_geocode)
    get("/geocode/link", AdminFacilityController, :resolve_map_link)
  end

  scope "/api/org/:organization_slug/admin", PaleeWeb do
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
  scope "/api/org/:organization_slug/staff", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :staff_only,
      :tenant_write_rate_limited
    ])

    get("/members", StaffController, :index)
    get("/clients/:user_id/coach-notes", CoachNotesController, :index)
    # ADR-229: a client's weekly goal, set by their coach or full-scope staff.
    get("/clients/:user_id/training-goal", TrainingGoalController, :client_show)
    put("/clients/:user_id/training-goal", TrainingGoalController, :client_update)
    get("/clients/:user_id/journal", JournalController, :client_journal)
    # ADR-158: shared body snapshots (audited in the client's access log).
    get("/clients/:user_id/body", ClientBodyController, :index)
    get("/clients/:user_id/body/snapshots/:id", ClientBodyController, :show)
    get("/clients/:user_id/body/series", ClientBodyController, :series)
    # ADR-160: the weekly wellness summary, only with the client's grant.
    get("/clients/:user_id/wellness-summary", ClientWellnessSummaryController, :show)
    # ADR-165: a client's coverage, qualities and load from shared entries.
    get("/clients/:user_id/progress-depth", TrainingDepthController, :client)
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
    # ADR-202: the cleaning schedule and the janitor's «Σήμερα».
    get("/cleaning/schedules", CleaningController, :schedules)
    put("/cleaning/schedules/:space_id", CleaningController, :put_schedule)
    delete("/cleaning/schedules/:space_id", CleaningController, :delete_schedule)
    get("/cleaning/today", CleaningController, :today)
    # ADR-202: Settings › Spaces.
    get("/spaces", SpacesController, :index)
    post("/spaces", SpacesController, :create)
    get("/spaces/:id", SpacesController, :show)
    patch("/spaces/:id", SpacesController, :update)
    post("/spaces/:id/archive", SpacesController, :archive)
    post("/spaces/:id/restore", SpacesController, :restore)
    post("/spaces/:id/unavailability", SpacesController, :make_unavailable)

    delete(
      "/spaces/:id/unavailability/:window_id",
      SpacesController,
      :delete_unavailability
    )

    post("/floor-plans/uploads", SpacesController, :floor_plan_upload)
    post("/floor-plans/uploads/:id/complete", SpacesController, :complete_floor_plan_upload)
    post("/floor-plans", SpacesController, :create_floor_plan)
    patch("/floor-plans/:id", SpacesController, :update_floor_plan)
    delete("/floor-plans/:id", SpacesController, :delete_floor_plan)
    get("/inventory/machines", InventoryController, :machines)
    post("/inventory/machines", InventoryController, :create_machine)
    patch("/inventory/machines/:id", InventoryController, :update_machine)
    post("/inventory/machines/:id/archive", InventoryController, :archive_machine)
    get("/inventory/machines/:id/events", InventoryController, :machine_events)
    put("/inventory/machines/:id/placements", InventoryController, :place_machine)
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
    # ADR-190: the e-shop.
    get("/shop/products", ShopController, :products)
    post("/shop/products", ShopController, :create_product)
    get("/shop/products/:id", ShopController, :product)
    patch("/shop/products/:id", ShopController, :update_product)
    put("/shop/products/:id/status", ShopController, :set_product_status)
    post("/shop/products/:id/variants", ShopController, :create_variant)
    patch("/shop/products/:id/variants/:variant_id", ShopController, :update_variant)
    post("/shop/products/:id/variants/:variant_id/archive", ShopController, :archive_variant)
    post("/shop/products/:id/promote", ShopController, :promote)
    get("/shop/promotion-codes", ShopController, :promotion_codes)
    patch("/shop/promotion-codes/:id", ShopController, :update_promotion_code)
    get("/shop/movements", ShopController, :ledger)
    get("/shop/payment-methods", ShopController, :payment_methods)
    post("/shop/photos", ShopController, :photo_upload)
    post("/shop/photos/:id/complete", ShopController, :complete_photo)
    get("/shop/variants/:id/movements", ShopController, :movements)
    post("/shop/variants/:id/movements", ShopController, :record_movement)
    get("/shop/orders", ShopController, :orders)
    get("/shop/orders/:id", ShopController, :order)
    get("/shop/orders/:id/lineage", ShopController, :lineage)
    post("/shop/orders/:id/ready", ShopController, :mark_ready)
    post("/shop/orders/:id/payment", ShopController, :record_payment)
    post("/shop/orders/:id/pickup", ShopController, :pick_up)
    post("/shop/orders/:id/cancel", ShopController, :cancel)
    post("/shop/orders/:id/refund", ShopController, :refund)
    put("/shop/orders/:id/fiscal-receipt", ShopController, :set_fiscal_receipt)
    post("/shop/desk-sales", ShopController, :desk_sale)
    get("/shop/ready-orders", ShopController, :ready_orders)
    get("/shop/revenue-streams", ShopController, :revenue_streams)
    get("/coaching-relationships", CoachingRelationshipsController, :index)
    post("/coaching-relationships", CoachingRelationshipsController, :create)
    post("/coaching-relationships/:id/end", CoachingRelationshipsController, :finish)
    get("/form-reviews", CoachingExtrasController, :form_review_queue)
    post("/form-reviews/:id/review", CoachingExtrasController, :complete_form_review)
    get("/reply-queue", CoachingExtrasController, :reply_queue)
    # ADR-174: the AI scaling approval queue.
    get("/scaling-suggestions", StaffScalingController, :index)
    post("/scaling-suggestions/:id/approve", StaffScalingController, :approve)
    post("/scaling-suggestions/:id/dismiss", StaffScalingController, :dismiss)
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

  # ADR-253: box screens, their pairing codes and overrides.
  scope "/api/org/:organization_slug/admin", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :admin_only,
      :tenant_write_rate_limited,
      :box_screen_code_rate_limited
    ])

    get("/box-screens", AdminBoxScreenController, :index)
    post("/box-screens", AdminBoxScreenController, :create)
    patch("/box-screens/:id", AdminBoxScreenController, :update)
    delete("/box-screens/:id", AdminBoxScreenController, :delete)
    post("/box-screens/:id/pairing-code", AdminBoxScreenController, :pairing_code)
    put("/box-screens/:id/override", AdminBoxScreenController, :put_override)
    delete("/box-screens/:id/override", AdminBoxScreenController, :delete_override)
  end

  scope "/api/org/:organization_slug/admin", PaleeWeb do
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
    post("/users/programming", AdminUserController, :program_workout_for_users)
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
    # ADR-186: the branches a staff member works at.
    put("/users/:id/location-scope", StaffLocationScopeController, :update)
    put("/users/:id/home-location", HomeLocationController, :update_member)
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
    # ADR-155: QR check-in desk, door display and rules.
    get("/check-in/door/:location_id", AdminCheckInController, :door)
    post("/check-in/door/:location_id/rotate", AdminCheckInController, :rotate_door)
    get("/check-in/door/:location_id/poster", AdminCheckInController, :poster)
    put("/check-in/door/:location_id/poster", AdminCheckInController, :update_poster)
    post("/check-in/door/:location_id/poster/rotate", AdminCheckInController, :rotate_poster)
    # ADR-173: NFC door tags.
    get("/check-in/door/:location_id/nfc", AdminCheckInController, :nfc_tag)
    put("/check-in/door/:location_id/nfc", AdminCheckInController, :update_nfc_tag)
    post("/check-in/door/:location_id/nfc/rotate", AdminCheckInController, :rotate_nfc_tag)
    delete("/check-in/members/:user_id/code", AdminCheckInController, :revoke_member_code)
    post("/check-in/scan-member", AdminCheckInController, :scan_member)
    post("/check-in/members/:user_id", AdminCheckInController, :check_in_member)
    get("/check-in/visitors", AdminCheckInController, :visitors)
    get("/check-in/settings", AdminCheckInController, :settings)
    put("/check-in/settings", AdminCheckInController, :update_settings)
    post("/class-types", AdminClassTypeController, :create)
    patch("/class-types/:id", AdminClassTypeController, :update)
    delete("/class-types/:id", AdminClassTypeController, :delete)
    get("/workouts", AdminWorkoutController, :index)
    get("/workouts/choices", AdminWorkoutChoiceController, :search)
    get("/workouts/choices/suggested", AdminWorkoutChoiceController, :suggested)
    get("/workout-folders", AdminWorkoutFolderController, :index)
    post("/workout-folders", AdminWorkoutFolderController, :create)
    patch("/workout-folders/:id", AdminWorkoutFolderController, :update)
    delete("/workout-folders/:id", AdminWorkoutFolderController, :delete)
    post("/workouts", AdminWorkoutController, :create)
    post("/workouts/dsl/parse", AdminWorkoutDslController, :parse)
    post("/workouts/timer-preview", AdminWorkoutTimerPreviewController, :create)
    post("/workouts/free-text/analyze", AdminWorkoutFreeTextController, :analyze)
    # ADR-180: whether the editor offers the assistant or text sections.
    get("/workouts/authoring-settings", AdminWorkoutFreeTextController, :authoring_settings)
    get("/workouts/dsl/manual", AdminWorkoutDslController, :manual)
    get("/workouts/:id/dsl", AdminWorkoutDslController, :show_authoring)
    post("/workouts/:id/dsl/publish", AdminWorkoutDslController, :publish)
    get("/workouts/:id", AdminWorkoutController, :show)
    get("/workouts/:id/goals", AdminWorkoutGoalsController, :show)
    put("/workouts/:id/goals", AdminWorkoutGoalsController, :update)
    get("/workouts/:id/goal-feedback-summary", AdminWorkoutGoalsController, :feedback_summary)
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
    get("/plan", AdminPlanController, :show)
    patch("/onboarding", AdminOnboardingController, :update)
    patch("/settings", AdminSettingsController, :update)
    put("/settings/time-zone", AdminSettingsController, :update_time_zone)
    # ADR-255: the settings catalog («Προχωρημένα») and the setup recipes.
    get("/setup/settings", AdminSetupController, :settings)
    get("/setup/recipes", AdminSetupController, :recipes)
    post("/setup/recipes/:key/preview", AdminSetupController, :preview)
    post("/setup/recipes/:key/apply", AdminSetupController, :apply_recipe)
    # ADR-174: the gym's AI settings (own key, scaling switch, usage).
    get("/ai-settings", AdminAiSettingsController, :show)
    put("/ai-settings", AdminAiSettingsController, :update)
    get("/branding", AdminBrandingController, :show)
    get("/trial-policy", AdminTrialController, :policy)
    put("/trial-policy", AdminTrialController, :update_policy)
    get("/trials", AdminTrialController, :queue)
    post("/trials/:id/accept", AdminTrialController, :accept)
    post("/trials/:id/decline", AdminTrialController, :decline)
    post("/trials/:id/attendance", AdminTrialController, :attendance)
    # ADR-191: partner perks.
    get("/perks", AdminPerkController, :index)
    post("/perks", AdminPerkController, :create)
    get("/perks/:id", AdminPerkController, :show)
    get("/perks/:id/versions", AdminPerkController, :versions)
    patch("/perks/:id", AdminPerkController, :update)
    delete("/perks/:id", AdminPerkController, :delete)
    post("/perks/:id/publish", AdminPerkController, :publish)
    post("/perks/:id/pause", AdminPerkController, :pause)
    post("/perks/:id/expire", AdminPerkController, :expire)
    post("/perks/:id/codes", AdminPerkController, :add_codes)
    get("/perks/:id/claims", AdminPerkController, :claims)
    get("/perks/:id/claims.csv", AdminPerkController, :claims_csv)
    post("/perk-claims/:id/use", AdminPerkController, :use_claim)
    post("/perk-claims/:id/revoke", AdminPerkController, :revoke_claim)
    # ADR-156: «Φέρε φίλο» invites.
    get("/referrals", AdminReferralController, :index)
    post("/referrals/:id/approve", AdminReferralController, :approve)
    post("/referrals/:id/reject", AdminReferralController, :reject)
    post("/referrals/:id/given", AdminReferralController, :given)
    put("/referrals/:id/referrer", AdminReferralController, :reassign)
    post("/referrals/:id/friend-gift", AdminReferralController, :friend_gift)
    # ADR-143: «Κοινότητα».
    get("/community/groups", AdminCommunityController, :groups)
    put("/community/groups/:id/decision", AdminCommunityController, :decide_group)
    post("/community/groups/:id/reopen", AdminCommunityController, :reopen_group)
    put("/community/settings", AdminCommunityController, :update_settings)
    get("/community/reports", AdminCommunityController, :reports)
    post("/community/reports/actions", AdminCommunityController, :act_on_report)
    get("/community/clubs", AdminCommunityController, :clubs)
    post("/community/clubs", AdminCommunityController, :create_club)
    get("/community/clubs/:id", AdminCommunityController, :club)
    patch("/community/clubs/:id", AdminCommunityController, :update_club)
    post("/community/clubs/:id/archive", AdminCommunityController, :archive_club)
    put("/community/clubs/:id/requests/:user_id", AdminCommunityController, :answer_club_request)
    delete("/community/clubs/:id/members/:user_id", AdminCommunityController, :remove_club_member)
    # ADR-153: club events.
    get("/community/events", AdminCommunityEventController, :index)
    post("/community/events", AdminCommunityEventController, :create)
    get("/community/events/:id", AdminCommunityEventController, :show)
    patch("/community/events/:id", AdminCommunityEventController, :update)
    post("/community/events/:id/cancel", AdminCommunityEventController, :cancel)
    post("/community/events/:id/message", AdminCommunityEventController, :message)
    post("/community/events/:id/trial-offer", AdminCommunityEventController, :trial_offer)

    put(
      "/community/events/:id/attendees/:user_id/check-in",
      AdminCommunityEventController,
      :check_in
    )

    put(
      "/community/events/:id/attendees/:user_id/paid",
      AdminCommunityEventController,
      :mark_paid
    )

    delete("/community/events/:id/attendees/:user_id", AdminCommunityEventController, :remove)
    # ADR-185: the organiser console (refunds, numbers) and co-hosting.
    put(
      "/community/events/:id/attendees/:user_id/refund",
      AdminCommunityEventController,
      :refund
    )

    get("/community/event-finances", AdminCommunityEventController, :finances)
    get("/community/event-analytics", AdminCommunityEventController, :analytics)
    get("/community/events/:id/cohosts", AdminCommunityEventController, :cohosts)
    post("/community/events/:id/cohosts", AdminCommunityEventController, :invite_cohost)

    delete(
      "/community/events/:id/cohosts/:cohost_id",
      AdminCommunityEventController,
      :remove_cohost
    )

    get("/community/cohost-requests", AdminCommunityEventController, :cohost_requests)

    post(
      "/community/cohost-requests/:id/answer",
      AdminCommunityEventController,
      :answer_cohost_request
    )

    post(
      "/community/cohost-requests/:id/trial-offer",
      AdminCommunityEventController,
      :cohost_trial_offer
    )

    get("/public-profile", AdminPublicProfileController, :show)
    put("/public-profile", AdminPublicProfileController, :update)
    post("/public-profile/publish", AdminPublicProfileController, :publish)
    post("/public-profile/unpublish", AdminPublicProfileController, :unpublish)
    post("/public-profile/suggestions", AdminPublicProfileController, :suggest)
    post("/public-profile/photos", AdminPublicProfileController, :photo_upload)
    post("/public-profile/photos/:id/complete", AdminPublicProfileController, :complete_photo)
    post("/branding/logo/upload-url", AdminBrandingController, :logo_upload_url)
    put("/branding/logo", AdminBrandingController, :finalize_logo)
    delete("/branding/logo", AdminBrandingController, :remove_logo)
    post("/schedule/slots", AdminScheduleController, :create_slot)
    post("/schedule/slots/series", AdminScheduleController, :create_series)
    patch("/schedule/slots/:id", AdminScheduleController, :update_slot)
    put("/schedule/slots/:id/workout", AdminScheduleController, :link_workout)
    # ADR-230: the WOD of a whole day.
    post("/schedule/slots/:id/day-workout", AdminDayWorkoutController, :follow_day)
    get("/schedule/day-workouts", AdminDayWorkoutController, :index)
    post("/schedule/day-workouts/preview", AdminDayWorkoutController, :preview)
    put("/schedule/day-workouts", AdminDayWorkoutController, :put)
    delete("/schedule/day-workouts/:id", AdminDayWorkoutController, :delete)
    post("/schedule/slots/:id/state", AdminScheduleController, :change_state)
    delete("/schedule/slots/:id", AdminScheduleController, :delete_slot)

    get(
      "/schedule/slots/:id/goal-feedback-summary",
      AdminWorkoutGoalsController,
      :class_feedback_summary
    )

    patch("/bookings/:id/approve", AdminScheduleController, :approve_booking)
    patch("/bookings/:id/reject", AdminScheduleController, :reject_booking)

    post(
      "/schedule/slots/:slot_id/attendance/:user_id",
      AdminScheduleController,
      :record_attendance
    )

    get("/athletes/:id/drill-down", AdminCoachingController, :drill_down)
    get("/finance/summary", AdminFinanceController, :summary)
    # ADR-240–242: legal identity, fiscal documents, journal, closings.
    get("/fiscal/countries", AdminFiscalController, :countries)
    get("/fiscal/identity", AdminFiscalController, :identity)
    put("/fiscal/identity", AdminFiscalController, :save_identity)
    get("/fiscal/documents", AdminFiscalController, :documents)
    get("/fiscal/documents/:id", AdminFiscalController, :document)
    post("/fiscal/documents/:id/credit-notes", AdminFiscalController, :credit)
    get("/fiscal/journal/verification", AdminFiscalController, :verify_journal)
    get("/fiscal/closings", AdminFiscalController, :closings)
    get("/fiscal/archive", AdminFiscalController, :archive)
    # ADR-244/245: tax categories, US sales tax, document files, accounting exports.
    get("/fiscal/tax-categories", AdminFiscalTaxController, :tax_categories)
    get("/fiscal/sales-tax-rates", AdminFiscalTaxController, :sales_tax_rates)
    put("/fiscal/sales-tax-rates", AdminFiscalTaxController, :save_sales_tax_rates)
    get("/fiscal/documents/:id/pdf", AdminFiscalTaxController, :document_pdf)
    get("/fiscal/documents/:id/html", AdminFiscalTaxController, :document_html)
    post("/fiscal/documents/:id/email", AdminFiscalTaxController, :email_document)
    get("/fiscal/registry-connection", AdminFiscalRegistryController, :connection)
    put("/fiscal/registry-connection", AdminFiscalRegistryController, :save_connection)
    get("/fiscal/registry/businesses/:tax_id", AdminFiscalRegistryController, :lookup)
    get("/fiscal/exports/formats", AdminFiscalTaxController, :export_formats)
    put("/fiscal/exports/settings/:format", AdminFiscalTaxController, :save_export_settings)
    get("/fiscal/exports/:format", AdminFiscalTaxController, :export)
    # ADR-243: reporting to the tax authority (myDATA).
    get("/fiscal/authority-connection", AdminFiscalReportingController, :connection)
    put("/fiscal/authority-connection", AdminFiscalReportingController, :save_connection)
    get("/fiscal/transmissions", AdminFiscalReportingController, :transmissions)

    post(
      "/fiscal/documents/:id/transmission/retry",
      AdminFiscalReportingController,
      :retry
    )

    # ADR-249: Tap to Pay at the desk (the provider's terminal app on a staff phone).
    get("/payments/terminal/availability", AdminTerminalPaymentsController, :availability)
    post("/payments/terminal", AdminTerminalPaymentsController, :create)
    post("/payments/terminal/result", AdminTerminalPaymentsController, :result)
    get("/payments/terminal/:id", AdminTerminalPaymentsController, :show)
    post("/payments/terminal/:id/cancel", AdminTerminalPaymentsController, :cancel)

    post(
      "/payments/terminal/:id/sandbox-complete",
      AdminTerminalPaymentsController,
      :sandbox_complete
    )

    # ADR-250: Peppol e-invoicing.
    get("/fiscal/peppol-connection", AdminFiscalEInvoicingController, :connection)
    put("/fiscal/peppol-connection", AdminFiscalEInvoicingController, :save_connection)
    get("/fiscal/einvoices", AdminFiscalEInvoicingController, :index)
    get("/fiscal/einvoices/:id", AdminFiscalEInvoicingController, :show)
    post("/fiscal/documents/:id/einvoice/retry", AdminFiscalEInvoicingController, :retry)
    # ADR-251: TSE (DE) and RKSV (AT) receipt signing.
    get("/fiscal/till-connections/:device", AdminFiscalTillSigningController, :connection)
    put("/fiscal/till-connections/:device", AdminFiscalTillSigningController, :save_connection)
    get("/fiscal/till-signatures", AdminFiscalTillSigningController, :index)

    post(
      "/fiscal/till-signatures/null-receipts",
      AdminFiscalTillSigningController,
      :null_receipt
    )

    get("/fiscal/till-signatures/:id", AdminFiscalTillSigningController, :show)
    post("/fiscal/till-signatures/:id/retry", AdminFiscalTillSigningController, :retry)

    # ADR-246/247: online payments through the business's provider account.
    get("/payments/account", AdminPaymentsController, :account)
    put("/payments/account", AdminPaymentsController, :save_account)
    put("/payments/account/options", AdminPaymentsController, :save_options)
    delete("/payments/account", AdminPaymentsController, :disconnect)
    post("/payments/connect", AdminPaymentsController, :connect)
    get("/payments/attention", AdminPaymentsController, :attention)
    get("/payments", AdminPaymentsController, :index)
    get("/payments/:id", AdminPaymentsController, :show)
    post("/payments/:id/refunds", AdminPaymentsController, :refund)
    post("/payments/:id/retry", AdminPaymentsController, :retry)
    post("/payments/:id/retry-charge", AdminPaymentsController, :retry_charge)
    post("/payments/:id/dismiss", AdminPaymentsController, :dismiss_charge)
    post("/payments/:id/card-link", AdminPaymentsController, :card_link)
    # ADR-252: documents, signatures and health certificates.
    get("/documents/templates", AdminDocumentsController, :index)
    post("/documents/templates", AdminDocumentsController, :create)
    get("/documents/starters", AdminDocumentsController, :starters)
    get("/documents/outstanding", AdminDocumentsController, :outstanding)
    get("/documents/templates/:id", AdminDocumentsController, :show)
    get("/documents/templates/:id/versions/:version_id", AdminDocumentsController, :version)
    post("/documents/templates/:id/versions", AdminDocumentsController, :publish)
    put("/documents/templates/:id/requirement", AdminDocumentsController, :set_requirement)
    post("/documents/templates/:id/archive", AdminDocumentsController, :archive)
    post("/documents/templates/:id/requests", AdminDocumentsController, :request)
    get("/documents/requests", AdminDocumentsController, :requests)
    post("/documents/requests/:id/cancel", AdminDocumentsController, :cancel_request)
    get("/documents/signatures", AdminDocumentsController, :signatures)
    get("/documents/signatures/:id/evidence", AdminDocumentsController, :evidence)
    get("/documents/members/:user_id", AdminDocumentsController, :member)
    get("/documents/settings", AdminDocumentsController, :settings)
    put("/documents/settings", AdminDocumentsController, :save_settings)
    get("/documents/audit", AdminDocumentsController, :audit)
    get("/documents/health-certificates", AdminHealthCertificatesController, :index)

    get(
      "/documents/health-certificates/members/:user_id",
      AdminHealthCertificatesController,
      :client
    )

    post(
      "/documents/health-certificates/uploads",
      AdminHealthCertificatesController,
      :request_upload
    )

    post("/documents/health-certificates", AdminHealthCertificatesController, :create)
    get("/documents/health-certificates/:id/file", AdminHealthCertificatesController, :file)
    delete("/documents/health-certificates/:id", AdminHealthCertificatesController, :delete)
    # ADR-254: CSV imports.
    get("/imports/catalog", AdminImportController, :catalog)
    get("/imports", AdminImportController, :index)
    post("/imports", AdminImportController, :create)
    get("/imports/:id", AdminImportController, :show)
    get("/imports/:id/rows", AdminImportController, :rows)
    post("/imports/:id/preview", AdminImportController, :preview)
    post("/imports/:id/apply", AdminImportController, :apply)
    post("/imports/:id/invitations", AdminImportController, :invitations)
    post("/imports/:id/undo", AdminImportController, :undo)
    delete("/imports/:id", AdminImportController, :delete)

    # ADR-192: shop reports, pricing indicators and revenue reconciliation.
    get("/shop/reports/overview", AdminShopReportController, :overview)
    get("/shop/reports/sales", AdminShopReportController, :sales)
    get("/shop/reports/products", AdminShopReportController, :products)
    get("/shop/reports/margin", AdminShopReportController, :margin)
    get("/shop/reports/channels", AdminShopReportController, :channels)
    get("/shop/reports/inventory", AdminShopReportController, :inventory)
    get("/shop/reports/attribution", AdminShopReportController, :attribution)
    get("/shop/reports/pricing", AdminShopReportController, :pricing)
    get("/shop/reports/reconciliation", AdminShopReportController, :reconciliation)
    get("/shop/pricing-targets", AdminShopReportController, :pricing_targets)
    put("/shop/pricing-targets", AdminShopReportController, :put_pricing_target)
    get("/finance/queues", AdminFinanceController, :operational_queues)
    get("/finance/cleanup-records", AdminFinanceController, :cleanup_records)
    post("/finance/cleanup-records/:id/purge", AdminFinanceController, :purge_record)
    # ADR-167: seasons.
    get("/seasons", AdminSeasonController, :index)
    post("/seasons", AdminSeasonController, :create)
    get("/seasons/:id", AdminSeasonController, :show)
    patch("/seasons/:id", AdminSeasonController, :update)
    post("/season-enrollments/:id/confirm", AdminSeasonController, :confirm)
    post("/season-enrollments/:id/decline", AdminSeasonController, :decline)
    post("/season-enrollments/:id/remove", AdminSeasonController, :remove)
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
    # ADR-220: renewal choice and leaving the box.
    put(
      "/finance/members/:id/subscriptions/:subscription_id/auto-renew",
      AdminFinanceController,
      :set_member_auto_renew
    )

    post("/finance/members/:id/leave", AdminFinanceController, :mark_member_left)
    delete("/finance/members/:id/leave", AdminFinanceController, :undo_member_left)
    post("/finance/members/:id/payments", AdminFinanceController, :record_payment)
    post("/finance/members/:id/payments/receive", AdminFinanceController, :receive_payment)
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

  scope "/api/platform", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :vendor,
      :platform_write_rate_limited
    ])

    get("/tag-suggestions", PlatformTagSuggestionController, :index)
    # ADR-218: the installation's Web Push keys (formerly in each gym's settings).
    get("/push-settings", PlatformPushSettingsController, :show)
    patch("/push-settings", PlatformPushSettingsController, :update)
    # ADR-187: the password reset security log.
    get("/password-reset-log", PasswordRecoveryController, :log)
    # ADR-170: platform plans, prices and each organization's plan.
    get("/plans", PlatformPlanController, :index)
    post("/plans", PlatformPlanController, :create)
    patch("/plans/:code", PlatformPlanController, :update)
    get("/subscriptions", PlatformPlanController, :subscriptions)
    put("/organizations/:id/plan", PlatformPlanController, :assign)
    patch("/tag-suggestions/:id", PlatformTagSuggestionController, :resolve)
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

    get(
      "/organizations/:id/invitations/:invitation_id/email",
      PlatformOrganizationController,
      :invitation_deliveries
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

  # ADR-184: business accounts in demo mode until the platform team activates
  # them: the business step of sign-up, requests and the activation link.
  scope "/api", PaleeWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited, :tenant_write_rate_limited])

    post("/business-accounts", BusinessAccountController, :sign_up)
    get("/me/business-requests", BusinessAccountController, :my_requests)
    post("/me/business-requests", BusinessAccountController, :request_conversion)
    post("/me/business-requests/:id/cancel", BusinessAccountController, :cancel_request)
    get("/me/archived-demos", BusinessAccountController, :archived_demos)
    post("/me/archived-demos/:id/reopen", BusinessAccountController, :reopen_demo)
    post("/business-activation/inspect", BusinessAccountController, :inspect_activation)
    post("/business-activation/redeem", BusinessAccountController, :redeem_activation)
  end

  # ADR-184: the floating demo-data button and the activation request.
  scope "/api/org/:organization_slug/admin", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :admin_only,
      :tenant_write_rate_limited
    ])

    get("/business", AdminBusinessController, :show)
    post("/business/demo-data", AdminBusinessController, :seed)
    delete("/business/demo-data", AdminBusinessController, :remove)
    post("/business/activation-request", AdminBusinessController, :request_activation)
  end

  # ADR-184: the vendors' queue and activation links.
  scope "/api/platform", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :vendor,
      :platform_write_rate_limited
    ])

    get("/business-accounts", PlatformBusinessAccountController, :queue)
    post("/business-requests/:id/decision", PlatformBusinessAccountController, :decide)
    post("/organizations/:id/activation-links", PlatformBusinessAccountController, :issue_link)
    delete("/activation-links/:id", PlatformBusinessAccountController, :revoke_link)
  end

  scope "/api/me", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :upload_rate_limited,
      :search_rate_limited
    ])

    patch("/profile", MeController, :update_profile)
    # ADR-207: the login's pending email change.
    get("/email-change", EmailChangeController, :show)
    post("/email-change", EmailChangeController, :create)
    post("/email-change/resend", EmailChangeController, :resend)
    delete("/email-change", EmailChangeController, :delete)
    post("/tours/:audience/complete", MeController, :complete_tour)
    put("/time-zone", MeController, :update_time_zone)
    post("/avatar/upload-url", MeController, :avatar_upload_url)
    patch("/avatar", MeController, :update_avatar)
    get("/search/users", MeController, :search_users)
    get("/places", MyPlacesController, :index)
  end

  scope "/api", PaleeWeb do
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
    get("/notifications/unread-count", NotificationController, :unread_count)
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
    # ADR-199: per-category notification choices (Εγώ › Ρυθμίσεις).
    get("/notifications/preferences", NotificationPreferenceController, :index)
    put("/notifications/preferences/:category", NotificationPreferenceController, :update)
    # ADR-171: push to the store apps.
    post("/notifications/native-push-tokens", NotificationController, :create_native_push_token)

    post(
      "/notifications/native-push-tokens/unregister",
      NotificationController,
      :delete_native_push_token
    )

    # ADR-173: the token the store app hands its home-screen widgets.
    post("/me/widget-tokens", WidgetController, :create_token)
    delete("/me/widget-tokens/:id", WidgetController, :delete_token)

    get("/wellbeing/injuries", WellbeingController, :index)
    post("/wellbeing/injuries", WellbeingController, :create)
    patch("/wellbeing/injuries/:id/heal", WellbeingController, :heal)
    patch("/wellbeing/injuries/:id", WellbeingController, :update)
    post("/wellbeing/injuries/:id/reopen", WellbeingController, :reopen)
    get("/wellbeing/check-ins", CheckInController, :index)
    post("/wellbeing/check-ins", CheckInController, :create)
    delete("/wellbeing/check-ins/:id", CheckInController, :delete)
    # ADR-183: «Τι κάνεις», asked by the first-run.
    get("/me/interests", MyInterestsController, :show)
    put("/me/interests", MyInterestsController, :update)
    get("/me/wellness", WellnessController, :show)
    post("/me/wellness/entries", WellnessController, :create_entry)
    patch("/me/wellness/entries/:id", WellnessController, :update_entry)
    delete("/me/wellness/entries/:id", WellnessController, :delete_entry)
    post("/me/wellness/cravings", WellnessController, :create_craving)
    patch("/me/wellness/cravings/:id", WellnessController, :update_craving)
    delete("/me/wellness/cravings/:id", WellnessController, :delete_craving)
    get("/me/wellness/preferences", WellnessController, :preferences)
    put("/me/wellness/preferences", WellnessController, :update_preferences)
    delete("/me/wellness", WellnessController, :erase)
    post("/me/wellness/meal-photos", WellnessController, :upload_meal_photo)
    get("/me/wellness/export", WellnessController, :export)
    post("/journal/comments/batch", JournalCommentController, :batch)
    put("/journal/comments/:id", JournalCommentController, :save)
    delete("/journal/comments/:id", JournalCommentController, :delete)
    get("/me/journal", JournalController, :index)
    # ADR-162: one journal across providers, Box ▾ and the merged «Σήμερα».
    get("/me/journal/coach-audience", JournalController, :coach_audience)
    put("/me/journal/coach-audience", JournalController, :put_coach_audience)

    # ADR-196: Εγώ › Κοινοποίηση › «Προεπιλογή νέων καταχωρήσεων».
    get("/me/journal/visibility-defaults", JournalController, :visibility_defaults)
    put("/me/journal/visibility-defaults", JournalController, :put_visibility_default)
    put("/me/journal/entries/:kind/:id/audience", JournalController, :entry_audience)
    post("/me/journal/export", JournalController, :export)
    get("/me/journal/exports", JournalController, :exports)
    get("/me/providers", MyProvidersController, :index)
    # ADR-191: partner perks at every provider the person is a client of.
    get("/me/perks", MyPerkController, :index)
    get("/me/perks/claims", MyPerkController, :claims)
    post("/me/perks/:id/claim", MyPerkController, :claim)
    post("/me/perks/claims/:id/verification-link", MyPerkController, :verification_link)
    put("/me/providers/selected", MyProvidersController, :select)
    get("/me/today", MyProvidersController, :today)
    # Εγώ › Πληρωμές: billing at every provider the person is a client of.
    get("/me/billing", MyBillingController, :index)
    get("/me/billing/transactions", MyBillingController, :transactions)
    get("/me/history", AccountTrainingController, :history)
    get("/me/progress", AccountTrainingController, :progress)
    # ADR-165: coverage summary, qualities radar and training load.
    get("/me/progress/depth", TrainingDepthController, :show)
    # ADR-166: the Πρόοδος insights slot.
    get("/me/insights", InsightsController, :show)
    post("/me/insights/restore", InsightsController, :restore)
    post("/me/insights/:rule/dismiss", InsightsController, :dismiss)
    get("/me/vault", AccountTrainingController, :vault)
    # ADR-164: the anatomy atlas, the member's coverage across providers.
    get("/me/atlas", AnatomyAtlasController, :show)
    # ADR-193: in-app walkthrough progress.
    get("/me/guides", GuideProgressController, :index)
    put("/me/guides/:guide_id", GuideProgressController, :update)
    delete("/me/guides/:guide_id", GuideProgressController, :delete)
    get("/me/filters/:surface", SavedFilterController, :show)
    put("/me/filters/:surface/last-used", SavedFilterController, :remember)
    post("/me/filters/:surface", SavedFilterController, :save)
    delete("/me/filters/:surface/:id", SavedFilterController, :delete)
    put("/me/filters/:surface/:id/alert", SavedFilterController, :alert)
    put("/me/journal/entries/:kind/:id/visibility", JournalController, :set_visibility)
    post("/me/journal/notes", JournalController, :create_note)
    patch("/me/journal/notes/:id", JournalController, :update_note)
    delete("/me/journal/notes/:id", JournalController, :delete_note)
    get("/me/clubs", CommunityController, :my_clubs)
    get("/me/feed", CommunityPostController, :feed)
    # ADR-143: open clubs, «Βρες», «Μέλη», reports, and posting in any club.
    get("/me/community/discover", OpenClubController, :discover)
    get("/me/clubs/:id/members", OpenClubController, :members)
    get("/me/open-clubs/:id", OpenClubController, :show)
    post("/me/open-clubs/:id/membership", OpenClubController, :join)
    delete("/me/open-clubs/:id/membership", OpenClubController, :leave)
    put("/me/open-clubs/:id/notify-level", OpenClubController, :set_notify_level)
    post("/me/community/reports", OpenClubController, :report)
    post("/me/community/posts", ClubPostController, :create)
    delete("/me/community/posts/:id", ClubPostController, :delete)
    put("/me/community/posts/:id/hidden", ClubPostController, :hide)
    put("/me/community/posts/:id/pinned", ClubPostController, :pin)
    put("/me/community/posts/:id/kudos", ClubPostController, :kudos)
    get("/me/community/posts/:id/comments", ClubPostController, :comments)
    post("/me/community/posts/:id/comments", ClubPostController, :comment)
    delete("/me/community/comments/:id", ClubPostController, :delete_comment)
    put("/me/community/comments/:id/hidden", ClubPostController, :hide_comment)
    # ADR-153: club events.
    get("/me/community/clubs/:id/events", CommunityEventController, :club_events)
    post("/me/community/clubs/:id/events", CommunityEventController, :create)
    get("/me/community/events", CommunityEventController, :clubs_events)
    get("/me/events", CommunityEventController, :mine)
    get("/me/events/:id", CommunityEventController, :show)
    patch("/me/events/:id", CommunityEventController, :update)
    post("/me/events/:id/cancel", CommunityEventController, :cancel)
    put("/me/events/:id/rsvp", CommunityEventController, :rsvp)
    post("/me/events/:id/invites", CommunityEventController, :invite)
    # ADR-185: «Διοργάνωση ως» and the event page's view count.
    get("/me/event-hosts", CommunityEventController, :hosts)
    post("/me/events/:id/views", CommunityEventController, :view)
    # ADR-142: follows, profile posts and people.
    get("/me/social", FollowController, :summary)
    put("/me/social/booking-sharing", FollowController, :booking_sharing)
    put("/me/social/member-visibility", FollowController, :member_visibility)
    put("/me/social/around-visibility", FollowController, :around_visibility)
    post("/me/follows", FollowController, :create)
    get("/me/follows/:target_type/:target_id", FollowController, :show)
    delete("/me/follows/:target_type/:target_id", FollowController, :delete)
    get("/me/follow-requests", FollowController, :requests)
    post("/me/follow-requests/:id/accept", FollowController, :accept)
    delete("/me/follow-requests/:id", FollowController, :remove)
    get("/me/followers", FollowController, :followers)
    delete("/me/followers/:id", FollowController, :remove)
    get("/me/following", FollowController, :following)
    # ADR-193: Buddies, privacy and person-to-person conversations.
    get("/me/buddies-list", FollowController, :buddies)
    put("/me/social/privacy", FollowController, :privacy)
    get("/me/conversations", PersonConversationController, :index)
    get("/me/conversations/unread-count", PersonConversationController, :unread_count)
    post("/me/conversations", PersonConversationController, :create)
    get("/me/conversations/:id", PersonConversationController, :show)
    get("/me/conversations/:id/messages", PersonConversationController, :messages)
    post("/me/conversations/:id/messages", PersonConversationController, :send_message)
    post("/me/conversations/:id/read", PersonConversationController, :read)
    post("/me/conversations/:id/accept", PersonConversationController, :accept)
    post("/me/conversations/:id/decline", PersonConversationController, :decline)
    get("/me/post-attachments/:type/:id", PostAttachmentController, :show)
    post("/profile-posts", ProfilePostController, :create)
    delete("/profile-posts/:id", ProfilePostController, :delete)
    put("/profile-posts/:id/kudos", ProfilePostController, :kudos)
    get("/profile-posts/:id/comments", ProfilePostController, :comments)
    post("/profile-posts/:id/comments", ProfilePostController, :comment)
    delete("/profile-post-comments/:id", ProfilePostController, :delete_comment)
    get("/people/:id", PeopleController, :show)
    get("/people/:id/posts", PeopleController, :posts)
    # Board 4 D2: only «Σχετικά» is public; the rest of a box page needs sign-in.
    get("/boxes/:slug/schedule", PublicBoxController, :schedule)
    get("/boxes/:slug/posts", PublicBoxController, :posts)
    # ADR-190: a published box's shop for anyone (signed in).
    get("/boxes/:slug/shop/products", MyShopController, :public_products)
    get("/boxes/:slug/events", CommunityEventController, :box_events)
    # ADR-156: the friend's side of an invite.
    post("/referrals/claim", ReferralController, :claim)
    # ADR-144: trials.
    post("/boxes/:slug/trials", TrialController, :create)
    get("/me/trials", TrialController, :index)
    get("/me/trials/:id", TrialController, :show)
    post("/me/trials/:id/cancel", TrialController, :cancel)
    post("/me/trials/:id/follow-up", TrialController, :follow_up)
    # ADR-158: Ημερολόγιο › Σώμα.
    get("/me/body/snapshots", MyBodyController, :index)
    post("/me/body/snapshots", MyBodyController, :create)
    get("/me/body/snapshots/:id", MyBodyController, :show)
    patch("/me/body/snapshots/:id", MyBodyController, :update)
    delete("/me/body/snapshots/:id", MyBodyController, :delete)
    post("/me/body/snapshots/:id/photos", MyBodyController, :add_photo)
    delete("/me/body/snapshots/:id/photos/:photo_id", MyBodyController, :remove_photo)
    get("/me/body/series", MyBodyController, :series)
    get("/me/body/compare", MyBodyController, :compare)
    get("/me/body/photos/latest", MyBodyController, :latest_photos)
    delete("/me/body/photos", MyBodyController, :delete_photos)
    get("/me/body/settings", MyBodyController, :settings)
    put("/me/body/settings", MyBodyController, :update_settings)
    get("/me/body/consents", MyBodyController, :consents)
    put("/me/body/consents/:scope", MyBodyController, :grant_consent)
    delete("/me/body/consents/:scope", MyBodyController, :withdraw_consent)
    get("/me/body/access-log", MyBodyController, :access_log)
    post("/me/body/share", MyBodyController, :share)
    # ADR-169: Partners.
    get("/me/clubs/:club_id/partners", PartnersController, :club)
    put("/me/clubs/:club_id/partners/profile", PartnersController, :put_profile)
    get("/me/clubs/:club_id/partners/deck", PartnersController, :deck)
    post("/me/clubs/:club_id/partners/swipes", PartnersController, :swipe)
    delete("/me/clubs/:club_id/partners/swipes/:target_id", PartnersController, :undo)
    get("/me/partners/matches", PartnersController, :matches)
    delete("/me/partners/matches/:id", PartnersController, :end_match)
    get("/me/partners/matches/:id/messages", PartnersController, :messages)
    post("/me/partners/matches/:id/messages", PartnersController, :post_message)
    post("/me/partners/matches/:id/messages/read", PartnersController, :mark_read)
    get("/me/partners/matches/:id/sessions", PartnersController, :sessions)
    post("/me/partners/matches/:id/plans", PartnersController, :plan)
    get("/me/partners/settings", PartnersController, :settings)
    put("/me/partners/settings", PartnersController, :put_settings)
    get("/me/blocks", PartnersController, :blocks)
    post("/me/blocks", PartnersController, :block)
    delete("/me/blocks/:user_id", PartnersController, :unblock)
    # ADR-160: Buddy για στήριξη.
    get("/me/buddies", MyBuddiesController, :index)
    get("/me/buddies/candidates", MyBuddiesController, :candidates)
    get("/me/buddies/settings", MyBuddiesController, :settings)
    put("/me/buddies/settings", MyBuddiesController, :update_settings)
    post("/me/buddies", MyBuddiesController, :invite)
    post("/me/buddies/invite-links", MyBuddiesController, :create_invite_link)
    # ADR-210: "Send by email" of a guest pass, buddy invite link or «Φέρε φίλο».
    post("/me/share-links/email", ShareLinkEmailController, :create)
    post("/me/buddies/:id/accept", MyBuddiesController, :accept)
    post("/me/buddies/:id/decline", MyBuddiesController, :decline)
    post("/me/buddies/:id/leave", MyBuddiesController, :leave)
    patch("/me/buddies/:id", MyBuddiesController, :update)
    get("/me/buddies/:id/messages", BuddyMessagesController, :index)
    post("/me/buddies/:id/messages", BuddyMessagesController, :create)
    post("/me/buddies/:id/messages/read", BuddyMessagesController, :read)
    post("/me/buddy-invites/:token/claim", MyBuddiesController, :claim)
    get("/me/support-requests", SupportRequestController, :index)
    post("/me/support-requests", SupportRequestController, :create)
    get("/me/support-requests/:id", SupportRequestController, :show)
    post("/me/support-requests/:id/undo", SupportRequestController, :undo)
    post("/me/support-requests/:id/replies", SupportRequestController, :reply)
    get("/me/wellness-summary-sharing", WellnessSummarySharingController, :show)

    get(
      "/me/wellness-summary-sharing/access-log",
      WellnessSummarySharingController,
      :access_log
    )

    put("/me/wellness-summary-sharing", WellnessSummarySharingController, :update)
  end

  # ADR-185: creating an event as yourself or a business has its own budget
  # on top of the per-host daily limit, so a script can't flood Γύρω μου.
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited,
      :event_create_rate_limited
    ])

    post("/me/events", CommunityEventController, :host_create)
  end

  # ADR-160: the public landing page of a buddy invite link.
  scope "/api/buddy-invites", PaleeWeb do
    pipe_through([:api, :public_invite_rate_limited])

    get("/:token", BuddyInviteController, :show)
  end

  # ADR-157: photos and videos for posts.
  scope "/api/me/media", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :media_upload_rate_limited
    ])

    get("/capabilities", MyMediaController, :capabilities)
    post("/uploads", MyMediaController, :upload)
    get("/:id", MyMediaController, :show)
    post("/:id/complete", MyMediaController, :complete)
    patch("/:id", MyMediaController, :update)
    delete("/:id", MyMediaController, :delete)
  end

  scope "/api/me/media", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :ai_suggestion_rate_limited
    ])

    post("/:id/alt-text-suggestion", MyMediaController, :suggest_alt_text)
  end

  # ADR-158: body photo uploads share the media upload limits.
  scope "/api/me/body/photos", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :media_upload_rate_limited
    ])

    post("/uploads", MyBodyController, :upload)
  end

  # ADR-155: the door scan (any box: the door says which) and connected devices.
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :check_in_rate_limited
    ])

    post("/check-in/scan", ScanCheckInController, :scan)
    delete("/check-in/scan/:undo_token", ScanCheckInController, :undo)
    # ADR-173: the arrival reminder's regions for the store apps.
    get("/me/check-in/geofences", ScanCheckInController, :geofences)
    get("/me/connected-devices", WalletController, :devices)
    delete("/me/wallet-passes/:id", WalletController, :revoke)
  end

  # ADR-253: the box screen (a TV): pairing, then its display token only.
  scope "/api/box-screen", PaleeWeb do
    pipe_through([:api, :box_screen_pairing])

    post("/pair", BoxScreenController, :pair)
  end

  scope "/api/box-screen", PaleeWeb do
    pipe_through([:api, :box_screen])

    get("/today", BoxScreenController, :today)
    post("/token", BoxScreenController, :token)
    get("/classes/:slot_id/timer", BoxScreenController, :class_timer)
  end

  scope "/api/widget", PaleeWeb do
    pipe_through([:api, :widget])

    get("/snapshot", WidgetController, :snapshot)
    post("/water", WidgetController, :add_water)
  end

  # ADR-161: Garmin in Συνδεδεμένες συσκευές and the journal's device card;
  # ADR-172: the phone's health data.
  scope "/api/me", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :device_rate_limited
    ])

    get("/devices", DevicesController, :index)
    get("/devices/summary", DevicesController, :summary)
    post("/devices/summary/seen", DevicesController, :seen)
    post("/devices/garmin/connect", DevicesController, :connect)
    patch("/devices/garmin", DevicesController, :update)
    post("/devices/garmin/sync", DevicesController, :sync)
    delete("/devices/garmin", DevicesController, :disconnect)
    get("/devices/garmin/pending", DevicesController, :pending)
    # ADR-172: Apple Health and Health Connect from the store apps.
    get("/devices/export", PhoneHealthController, :export)
    post("/devices/phone/:provider/connect", PhoneHealthController, :connect)
    patch("/devices/phone/:provider", PhoneHealthController, :update)
    post("/devices/phone/:provider/ingest", PhoneHealthController, :ingest)
    delete("/devices/phone/:provider", PhoneHealthController, :disconnect)
    post("/device-imports/:id/confirm", DevicesController, :confirm)
    get("/daily-stats", DevicesController, :daily_stats)
  end

  # ADR-154: Γύρω μου, «Η περιοχή μου» and the gazetteer; members only.
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :around_rate_limited
    ])

    post("/around/search", AroundController, :search)
    post("/around/search/:kind", AroundController, :kind)
    post("/around/pins", AroundController, :pins)
    get("/places/neighbourhoods", PlacesController, :neighbourhoods)
    post("/places/neighbourhoods/import", PlacesController, :import)
    get("/me/around/area", PlacesController, :area)
    put("/me/around/area", PlacesController, :update_area)
  end

  # ADR-144, board 6 Q6: talking to a box from its page.
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :messaging_rate_limited
    ])

    get("/me/box-conversations", BoxConversationController, :index)
    get("/boxes/:slug/conversation", BoxConversationController, :show)
    post("/boxes/:slug/conversation", BoxConversationController, :open)
    post("/boxes/:slug/conversation/messages", BoxConversationController, :send_message)
    post("/boxes/:slug/conversation/read", BoxConversationController, :mark_read)
  end

  scope "/api/workouts", PaleeWeb do
    pipe_through([:api, :authenticated, :authenticated_rate_limited, :user_only])

    get("/:id/timer-sequence", ExecutionController, :timer_sequence)
  end

  scope "/api/executions", PaleeWeb do
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
  scope "/api/executions", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :execution_interaction_rate_limited
    ])

    post("/:id/interactions", ExecutionController, :record_interactions)
  end

  scope "/api/gamification", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited
    ])

    get("/preferences", GamificationPreferencesController, :show)
    put("/preferences", GamificationPreferencesController, :update)
    # ADR-229: the weekly workout goal is the person's own.
    get("/goal", TrainingGoalController, :show)
    put("/goal", TrainingGoalController, :update)
  end

  scope "/api/prs", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :tenant_write_rate_limited
    ])

    get("/", PRController, :index)
    get("/history", PRController, :all_history)
    post("/", PRController, :create)
    patch("/:id/edit", PRController, :edit)
    patch("/:id", PRController, :update)
    delete("/:id", PRController, :delete)
    get("/:id/history", PRController, :history)
    post("/:id/share", PRController, :share)
    # ADR-196: a PR on the profile for followers, and a profile's PRs.
    put("/:id/profile-audience", PRController, :profile_audience)
    get("/profile/:user_id", PRController, :profile)
  end

  # ADR-193 §4: people search across Palee, in the personal session.
  scope "/api", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :search_rate_limited
    ])

    get("/people-search", PeopleController, :search)
    # ADR-221: boxes and independent coaches by name.
    get("/box-search", BoxSearchController, :index)
  end

  # ADR-129: personal PR sharing (global, not tenant-scoped).
  scope "/api/pr-sharing", PaleeWeb do
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

  scope "/api/pr-sharing", PaleeWeb do
    pipe_through([
      :api,
      :authenticated,
      :authenticated_rate_limited,
      :user_only,
      :grantee_lookup_rate_limited
    ])

    get("/grantee-lookup", PRSharingController, :lookup_grantee)
  end

  if Application.compile_env(:palee, :dev_routes) do
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through([:fetch_session, :protect_from_forgery])

      live_dashboard("/dashboard", metrics: PaleeWeb.Telemetry)
      forward("/mailbox", Plug.Swoosh.MailboxPreview)
    end
  end

  def open_api_spec do
    PaleeWeb.ApiSpec.spec()
  end
end
