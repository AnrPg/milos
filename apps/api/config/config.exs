# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :palee,
  ecto_repos: [Palee.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: config_env()

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_compression: :gzip

config :palee, Oban,
  repo: Palee.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", Palee.Workers.RefreshLeaderboardJob},
       {"*/15 * * * *", Palee.Workers.RefreshFinanceAggregatesJob},
       {"*/15 * * * *", Palee.Workers.RefreshCoachingAggregatesJob},
       {"0 2 * * *", Palee.Workers.MarkOverdueInvoicesJob},
       {"17 * * * *", Palee.Workers.ReconcileEntitlementReservationsJob},
       {"0 9 * * *", Palee.Workers.PaymentReminderJob},
       {"41 * * * *", Palee.Workers.ExecutionAbandonmentSweepJob},
       {"*/30 * * * *", Palee.Workers.RebuildMemberSearchIndexJob},
       {"0 8 * * *", Palee.Workers.PackageExpiryReminderJob},
       {"23 * * * *", Palee.Workers.CoachingReplyOverdueJob},
       {"41 6 * * *", Palee.Workers.CorporateInvoicingJob},
       {"7 7 * * *", Palee.Workers.InventoryDigestJob},
       {"11 * * * *", Palee.Workers.ShopOrderSweepJob},
       # ADR-192: shop orders == shop invoice lines == payments - refunds.
       {"25 3 * * *", Palee.Workers.ShopRevenueReconciliationJob},
       {"30 8 * * *", Palee.Workers.SubscriptionExpiryJob},
       {"13 * * * *", Palee.Workers.ProvisionGymClubsJob},
       {"52 * * * *", Palee.Workers.SweepOrphanMediaJob},
       {"37 3 * * *", Palee.Workers.SweepOrphanMediaJob, args: %{"dangling" => true}},
       {"20 4 * * *", Palee.Workers.ArchiveQuietGroupsJob},
       {"35 4 * * *", Palee.Workers.OrganiserCleanupJob},
       {"50 4 * * *", Palee.Workers.AbandonedDemosJob},
       {"*/10 * * * *", Palee.Workers.EventRemindersJob},
       {"*/5 * * * *", Palee.Workers.ClassWorkoutAlertsJob},
       {"0 7 * * *", Palee.Workers.AroundAlertsJob},
       {"30 9 * * *", Palee.Workers.BodyRemindersJob},
       {"0,30 * * * *", Palee.Workers.BuddyWeeklySummaryJob},
       {"*/10 * * * *", Palee.Workers.WellnessNudgesJob},
       {"*/15 * * * *", Palee.Workers.DeviceMaintenanceJob},
       {"10 1 * * *", Palee.Workers.SeasonSweepJob},
       {"40 2 * * *", Palee.Workers.NightlyInsightsJob},
       {"27 * * * *", Palee.Workers.ScalingSuggestionScanJob},
       {"47 * * * *", Palee.Workers.WorldGazetteerJob},
       # ADR-212: email retention and the SMTP key's expiry check.
       {"15 3 * * *", Palee.Workers.EmailRetentionJob},
       {"5 7 * * *", Palee.Workers.SmtpKeyExpiryJob},
       # ADR-211: self-service account deletions whose grace is over.
       {"19 * * * *", Palee.Workers.ExecuteAccountDeletionsJob},
       # ADR-242: fiscal day/month/year closings on each gym's own clock.
       {"20 * * * *", Palee.Workers.CloseFiscalPeriodsJob},
       # ADR-243: retries and deferred reports to the tax authority.
       {"*/5 * * * *", Palee.Workers.TransmitFiscalDocumentsJob},
       # ADR-246/247: settle online payments; hourly autopay of due invoices.
       {"*/3 * * * *", Palee.Workers.ProcessPaymentsJob},
       {"11 * * * *", Palee.Workers.ProcessPaymentsJob, args: %{"autopay" => true}}
     ]}
  ],
  queues: [
    default: 10,
    notifications: 20,
    gamification: 5,
    analytics: 3,
    # ADR-157: photo and video processing is CPU-bound.
    media: 2,
    # ADR-203: outbox delivery. Two at a time keeps the daily budget close
    # to exact (each job counts today's sent mail before it sends).
    email: 2,
    # ADR-243: reports to the tax authority (one HTTP call per document).
    fiscal: 2,
    # ADR-246: provider calls for online payments.
    payments: 2
  ]

config :palee, Palee.Infrastructure.Auth.Guardian,
  issuer: {Palee.Infrastructure.Auth.Guardian, :fetch_issuer, []},
  secret_key: {Palee.Infrastructure.Auth.Guardian, :fetch_secret, []},
  token_ttl: %{"access" => {15, :minutes}, "refresh" => {30, :days}}

config :palee,
       :workout_icon_suggester,
       Palee.Infrastructure.Ai.GeminiWorkoutIconSuggester

config :palee, :geocoder, Palee.Infrastructure.Facility.GovernedGeocoder

config :palee, :geocoder_governor,
  backend: Palee.Infrastructure.Facility.PhotonGeocoder,
  tiers: [[base_url: "https://photon.komoot.io", max_per_minute: 60]],
  cache_ttl_s: 86_400

config :palee,
       :map_link_resolver,
       Palee.Infrastructure.Facility.HttpMapLinkResolver

config :palee, :start_redix, true
config :palee, :start_oban, true
# ADR-123: a started execution not completed within this many hours is recorded
# as workout_execution_abandoned by ExecutionAbandonmentSweepJob.
config :palee, :execution_abandonment_hours, 6
config :palee, :redis_url, System.get_env("REDIS_URL", "redis://localhost:6379")
config :palee, :readiness_checker, Palee.Infrastructure.Readiness.Live
config :palee, :identity_user_store, Palee.Infrastructure.Identity.EctoUserStore
config :palee, :password_reset_store, Palee.Infrastructure.Identity.EctoPasswordResetStore
config :palee, :login_device_store, Palee.Infrastructure.Identity.EctoLoginDeviceStore
# ADR-206: "forgot password" requests are worked out in a background job.
config :palee, :password_reset_queue, Palee.Infrastructure.Identity.ObanPasswordResetQueue

config :palee,
       :organization_store,
       Palee.Infrastructure.Organizations.EctoOrganizationStore

# ADR-186: which branches a staff membership works at.
config :palee,
       :location_scope_store,
       Palee.Infrastructure.Organizations.EctoLocationScopeStore

config :palee, :coaching_store, Palee.Infrastructure.Coaching.EctoCoachingStore

config :palee,
       :facility_store,
       Palee.Infrastructure.Facility.EctoFacilityStore

config :palee, :content_store, Palee.Infrastructure.Content.EctoContentStore

config :palee,
       :appointment_store,
       Palee.Infrastructure.Appointments.EctoAppointmentStore

config :palee,
       :coaching_form_review_store,
       Palee.Infrastructure.Coaching.EctoFormReviewStore

config :palee,
       :housekeeping_store,
       Palee.Infrastructure.Housekeeping.EctoHousekeepingStore

config :palee,
       :inventory_store,
       Palee.Infrastructure.Inventory.EctoInventoryStore

# ADR-202: the spaces of each branch, their floor plans and unavailability.
config :palee, :space_store, Palee.Infrastructure.Spaces.EctoSpaceStore
# ADR-240–242: Fiscal (legal identity, documents, inalterable journal).
config :palee, :fiscal_store, Palee.Infrastructure.Fiscal.EctoFiscalStore
config :palee, :fiscal_journal_signer, Palee.Infrastructure.Fiscal.Ed25519JournalSigner
config :palee, :fiscal_transmission_store, Palee.Infrastructure.Fiscal.EctoTransmissionStore

# ADR-243: the gateway that reports documents, per connection environment.
config :palee, :fiscal_authority_gateways, %{
  "sandbox" => Palee.Infrastructure.Fiscal.SandboxAuthorityGateway,
  "test" => Palee.Infrastructure.Fiscal.MyDataGateway,
  "production" => Palee.Infrastructure.Fiscal.MyDataGateway
}

# ADR-246/247: online payments through the business's own provider account.
config :palee, :payment_store, Palee.Infrastructure.Payments.EctoPaymentStore
config :palee, :payment_fulfilment, Palee.Application.Payments.FinanceFulfilment

config :palee, :payment_gateways, %{
  "sandbox" => Palee.Infrastructure.Payments.SandboxGateway,
  "viva" => Palee.Infrastructure.Payments.VivaGateway,
  "stripe" => Palee.Infrastructure.Payments.StripeGateway
}

# ADR-190: the e-shop and Finance's revenue streams.
config :palee, :shop_store, Palee.Infrastructure.Shop.EctoShopStore
config :palee, :shop_notifier, Palee.Infrastructure.Shop.NotificationsShopNotifier

config :palee,
       :finance_revenue_stream_store,
       Palee.Infrastructure.Finance.EctoRevenueStreamStore

# No card vendor yet (ADR-190): the mock provider reports online payment as
# unavailable. Dev and test switch it to `:simulate` to exercise the paid flow.
config :palee, :shop_payment_provider, Palee.Infrastructure.Shop.MockPaymentProvider
config :palee, Palee.Infrastructure.Shop.MockPaymentProvider, mode: :unavailable

config :palee,
       :community_store,
       Palee.Infrastructure.Community.EctoCommunityStore

config :palee,
       :community_social_store,
       Palee.Infrastructure.Community.EctoSocialStore

config :palee,
       :conversation_store,
       Palee.Infrastructure.Conversations.EctoConversationStore

config :palee,
       :community_event_store,
       Palee.Infrastructure.Community.EctoEventStore

config :palee,
       :event_payments,
       Palee.Infrastructure.Finance.FinanceEventPayments

config :palee, :trial_store, Palee.Infrastructure.Trials.EctoTrialStore
config :palee, :season_store, Palee.Infrastructure.Seasons.EctoSeasonStore
# ADR-174: AI scaling suggestions (the advisor runs on the gym's own key).
config :palee, :scaling_store, Palee.Infrastructure.Scaling.EctoScalingStore
config :palee, :scaling_advisor, Palee.Infrastructure.Ai.AnthropicScalingAdvisor
# ADR-175: voice logging (speech to text on the platform key, parsing on the gym's key).
config :palee,
       :speech_transcriber,
       Palee.Infrastructure.Ai.GeminiSpeechTranscriber

config :palee,
       :log_draft_parser,
       Palee.Infrastructure.Ai.AnthropicLogDraftParser

config :palee, :trial_scheduler, Palee.Infrastructure.Trials.ObanTrialScheduler

config :palee,
       :referral_store,
       Palee.Infrastructure.Referrals.EctoReferralStore

# ADR-191: partner perks.
config :palee, :perk_store, Palee.Infrastructure.Perks.EctoPerkStore

# ADR-144: reactions to facts other contexts announce (Palee.DomainEvents).
config :palee, :domain_event_handlers, %{
  membership_activated: [
    Palee.Application.TrialReactions,
    Palee.Application.EventReactions,
    Palee.Application.ReferralReactions
  ],
  attendance_recorded: [
    Palee.Application.TrialReactions,
    Palee.Application.ReferralReactions,
    Palee.Application.WalletReactions
  ],
  # ADR-156: the invite funnel follows events, trials, joining and paying.
  event_attendance_recorded: [Palee.Application.ReferralReactions],
  membership_payment_recorded: [Palee.Application.ReferralReactions],
  booking_cancelled: [
    Palee.Application.TrialReactions,
    Palee.Application.WalletReactions
  ],
  booking_made: [Palee.Application.WalletReactions],
  class_cancelled: [Palee.Application.TrialReactions]
}

config :palee,
       :saved_filter_store,
       Palee.Infrastructure.Identity.EctoSavedFilterStore

config :palee, :media_store, Palee.Infrastructure.Media.EctoMediaStore

# ADR-157: post photos and videos. ImageMagick and ffmpeg ship in the API
# image; alt text suggestions use Gemini when configured.
config :palee,
       :image_processor,
       Palee.Infrastructure.Media.ImageMagickProcessor

config :palee, :video_transcoder, Palee.Infrastructure.Media.FfmpegTranscoder
config :palee, :image_describer, Palee.Infrastructure.Ai.GeminiImageDescriber

# ADR-154: Γύρω μου.
config :palee,
       :discovery_store,
       Palee.Infrastructure.Places.EctoDiscoveryStore

config :palee, :gazetteer_store, Palee.Infrastructure.Places.EctoGazetteerStore
config :palee, :world_gazetteer_source, Palee.Infrastructure.Places.GeonamesSource
config :palee, :home_area_store, Palee.Infrastructure.Places.EctoHomeAreaStore
config :palee, :interests_store, Palee.Infrastructure.Interests.EctoInterestsStore

config :palee,
       :public_profile_store,
       Palee.Infrastructure.Organizations.EctoPublicProfileStore

config :palee,
       :coaching_note_store,
       Palee.Infrastructure.Coaching.EctoNoteStore

config :palee,
       :coaching_relationship_store,
       Palee.Infrastructure.Coaching.EctoRelationshipStore

config :palee,
       :ai_usage_store,
       Palee.Infrastructure.AiUsage.EctoAiUsageStore

config :palee,
       :nutrition_store,
       Palee.Infrastructure.Nutrition.EctoNutritionStore

config :palee,
       :execution_store,
       Palee.Infrastructure.Execution.EctoExecutionStore

config :palee,
       :class_timer_store,
       Palee.Infrastructure.Execution.EctoClassTimerStore

config :palee,
       :training_log_store,
       Palee.Infrastructure.Execution.EctoTrainingLogStore

config :palee, :finance_store, Palee.Infrastructure.Finance.EctoFinanceStore

# ADR-192: the shop's report read model.
config :palee, :shop_report_store, Palee.Infrastructure.Shop.EctoShopReportStore

config :palee,
       :finance_accounting_store,
       Palee.Infrastructure.Finance.EctoFinanceAccountingStore

config :palee, :workout_store, Palee.Infrastructure.Workouts.EctoWorkoutStore

config :palee,
       :workout_goal_store,
       Palee.Infrastructure.Workouts.EctoGoalStore

config :palee,
       :workout_text_analyzer,
       Palee.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer

config :palee,
       :gamification_store,
       Palee.Infrastructure.Gamification.EctoGamificationStore

config :palee,
       :scheduling_store,
       Palee.Infrastructure.Scheduling.EctoSchedulingStore

# ADR-230: day WODs and their inheritance by the day's classes.
config :palee, :day_workout_store, Palee.Infrastructure.Scheduling.EctoDayWorkoutStore

config :palee, :pr_store, Palee.Infrastructure.Pantheon.EctoPRStore
config :palee, :journal_store, Palee.Infrastructure.Journal.EctoJournalStore

config :palee,
       :goal_feedback_store,
       Palee.Infrastructure.Journal.EctoGoalFeedbackStore

config :palee, :body_store, Palee.Infrastructure.Body.EctoBodyStore
config :palee, :buddy_store, Palee.Infrastructure.Buddies.EctoBuddyStore
config :palee, :partner_store, Palee.Infrastructure.Partners.EctoPartnerStore

config :palee,
       :support_scheduler,
       Palee.Infrastructure.Buddies.ObanSupportScheduler

# ADR-160: «Χρειάζομαι στήριξη» from Λιγούρα (the port M11 calls).
config :palee, :support_requests, Palee.Application.SupportRequests

config :palee,
       :push_subscription_store,
       Palee.Infrastructure.Notifications.EctoPushSubscriptionStore

config :palee,
       :notification_store,
       Palee.Infrastructure.Notifications.EctoNotificationStore

# ADR-199: per-category notification choices.
config :palee,
       :notification_preference_store,
       Palee.Infrastructure.Notifications.EctoNotificationPreferenceStore

# ADR-171: push to the store apps. Credentials come from runtime config
# (runtime.exs); without them a provider is off and registration answers 503.
config :palee,
       :native_push_token_store,
       Palee.Infrastructure.Notifications.EctoNativePushTokenStore

# ADR-173: the app installs whose home-screen widgets hold a widget token.
config :palee,
       :widget_token_store,
       Palee.Infrastructure.Widgets.EctoWidgetTokenStore

config :palee, :native_push_senders, %{
  fcm: Palee.Infrastructure.Notifications.FcmSender,
  apns: Palee.Infrastructure.Notifications.ApnsSender
}

config :palee, :feedback_store, Palee.Infrastructure.Feedback.EctoFeedbackStore

config :palee,
       :wellbeing_store,
       Palee.Infrastructure.Wellbeing.EctoWellbeingStore

config :palee,
       :wellness_store,
       Palee.Infrastructure.Wellness.EctoWellnessStore

config :palee,
       :insight_store,
       Palee.Infrastructure.Insights.EctoInsightStore

config :palee,
       :guide_progress_store,
       Palee.Infrastructure.Guides.EctoGuideProgressStore

config :palee,
       :messaging_thread_store,
       Palee.Infrastructure.Messaging.EctoThreadStore

config :palee,
       :messaging_message_store,
       Palee.Infrastructure.Messaging.EctoMessageStore

config :palee, :avatar_storage, Palee.Infrastructure.Storage.MinioStorage
config :palee, :document_storage, Palee.Infrastructure.Storage.MinioStorage
config :palee, :tenant_object_store, Palee.Infrastructure.Storage.MinioStorage
config :palee, :landing_cache, Palee.Infrastructure.Cache.LandingCache

config :palee,
       :pr_search_index,
       Palee.Infrastructure.Search.MeilisearchPRIndex

config :palee,
       :signed_token,
       Palee.Infrastructure.Security.PhoenixSignedToken

config :palee, :public_base_url, "http://localhost:4000"

# ADR-155: Wallet cards. Credentials come from runtime config (runtime.exs);
# without them each platform reports wallet_not_configured.
config :palee, :wallet_store, Palee.Infrastructure.Wallet.EctoWalletStore

config :palee, :wallet_pass_builders, %{
  apple: Palee.Infrastructure.Wallet.ApplePassBuilder,
  google: Palee.Infrastructure.Wallet.GooglePassBuilder
}

config :palee, :wallet_pass_updaters, %{
  apple: Palee.Infrastructure.Wallet.ApnsPassUpdater,
  google: Palee.Infrastructure.Wallet.GoogleWalletUpdater
}

config :palee,
       :wallet_image_source,
       Palee.Infrastructure.Wallet.HttpImageSource

# ADR-155: door codes, member codes and Wallet barcodes.
config :palee,
       :key_derivation,
       Palee.Infrastructure.Security.PhoenixKeyDerivation

config :palee,
       :realtime_publisher,
       Palee.Infrastructure.Realtime.PhoenixRealtimePublisher

config :palee,
       :admin_member_search_index,
       Palee.Infrastructure.Search.MeilisearchMemberIndex

config :palee,
       :identity_password_hasher,
       Palee.Infrastructure.Auth.PasswordHasher

config :palee, :rate_limiter, Palee.Infrastructure.Security.RedisRateLimiter
config :palee, :token_store, Palee.Infrastructure.Security.RedisTokenStore
config :palee, :token_issuer, Palee.Infrastructure.Auth.GuardianTokenIssuer
config :palee, :token_verifier, Palee.Infrastructure.Auth.GuardianTokenVerifier
config :palee, :password_verifier, Palee.Infrastructure.Auth.Password

config :palee,
       :remote_ip,
       headers: ["x-forwarded-for"],
       proxies: [{127, 0, 0, 1}, {10, 0, 0, 0, 8}, {172, 16, 0, 0, 12}, {192, 168, 0, 0, 16}]

# Configures the endpoint
config :palee, PaleeWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: PaleeWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Palee.PubSub,
  live_view: [signing_salt: "aRnuRHSQ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :palee, Palee.Mailer, adapter: Swoosh.Adapters.Local

# Overridden for prod in runtime.exs (MAIL_FROM_NAME/MAIL_FROM_ADDRESS); this
# default is fine for dev/test, where mail never actually leaves the box.
config :palee, :mail_from, name: "Palee", address: "no-reply@example.com"

# ADR-203: the transactional email outbox, its links and the sender.
config :palee, :email_message_store, Palee.Infrastructure.Email.EctoMessageStore
config :palee, :email_link_token_store, Palee.Infrastructure.Email.EctoLinkTokenStore
config :palee, :email_sender, Palee.Infrastructure.Email.SwooshSender
config :palee, :email_budget, daily_budget: 280, hard_cap: 295
# ADR-212: Brevo's webhook secret and the SMTP key's expiry (runtime env).
config :palee, :brevo_webhook_secret, nil
config :palee, :smtp_key_expires_on, nil

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "timestamp=$time level=$level $metadata message=\"$message\"\n",
  metadata: [
    :request_id,
    :user_id,
    :user_role,
    :job_id,
    :oban_job_id,
    # ADR-190 shop structured logs
    :organization_id,
    :shop_event,
    :order_id,
    :product_id,
    :variant_id,
    :channel,
    :amount_cents,
    # ADR-192 shop revenue reconciliation
    :event,
    :error,
    :day,
    :currency,
    :orders_cents,
    :invoice_lines_cents,
    :payments_cents,
    :drift_cents
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
# Request parameters never logged: keys, and ADR-175 voice clips and transcripts.
config :phoenix, :filter_parameters, ["password", "secret", "api_key", "audio", "transcript"]

config :open_api_spex, :json_render_error_v2, true

# Cache the API spec once; see PaleeWeb.OpenApiSpecCache (ADR-134) for
# why the default adapter exhausts the VM's literal area.
config :open_api_spex, :cache_adapter, PaleeWeb.OpenApiSpecCache

# ADR-184 follow-up: an idle demo business gets one reminder after
# `reminder_after_days` and is archived after `archive_after_days` (at least
# the difference after its reminder). Owner activity is written at most once
# per `touch_interval_seconds`.
config :palee, :abandoned_demos,
  reminder_after_days: 60,
  archive_after_days: 90,
  touch_interval_seconds: 3_600

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
