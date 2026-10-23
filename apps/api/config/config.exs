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
       {"30 8 * * *", Palee.Workers.SubscriptionExpiryJob},
       {"13 * * * *", Palee.Workers.ProvisionGymClubsJob},
       {"52 * * * *", Palee.Workers.SweepOrphanMediaJob},
       {"37 3 * * *", Palee.Workers.SweepOrphanMediaJob, args: %{"dangling" => true}},
       {"20 4 * * *", Palee.Workers.ArchiveQuietGroupsJob},
       {"35 4 * * *", Palee.Workers.OrganiserCleanupJob},
       {"*/10 * * * *", Palee.Workers.EventRemindersJob},
       {"*/5 * * * *", Palee.Workers.ClassWorkoutAlertsJob},
       {"0 7 * * *", Palee.Workers.AroundAlertsJob},
       {"30 9 * * *", Palee.Workers.BodyRemindersJob},
       {"0,30 * * * *", Palee.Workers.BuddyWeeklySummaryJob},
       {"*/10 * * * *", Palee.Workers.WellnessNudgesJob},
       {"*/15 * * * *", Palee.Workers.DeviceMaintenanceJob},
       {"10 1 * * *", Palee.Workers.SeasonSweepJob},
       {"40 2 * * *", Palee.Workers.NightlyInsightsJob},
       {"27 * * * *", Palee.Workers.ScalingSuggestionScanJob}
     ]}
  ],
  queues: [
    default: 10,
    notifications: 20,
    gamification: 5,
    analytics: 3,
    # ADR-157: photo and video processing is CPU-bound.
    media: 2
  ]

config :palee, Palee.Infrastructure.Auth.Guardian,
  issuer: {Palee.Infrastructure.Auth.Guardian, :fetch_issuer, []},
  secret_key: {Palee.Infrastructure.Auth.Guardian, :fetch_secret, []},
  token_ttl: %{"access" => {15, :minutes}, "refresh" => {30, :days}}

config :palee,
       :workout_icon_suggester,
       Palee.Infrastructure.Ai.GeminiWorkoutIconSuggester

config :palee, :geocoder, Palee.Infrastructure.Facility.PhotonGeocoder

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

config :palee,
       :organization_store,
       Palee.Infrastructure.Organizations.EctoOrganizationStore

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

config :palee,
       :community_store,
       Palee.Infrastructure.Community.EctoCommunityStore

config :palee,
       :community_social_store,
       Palee.Infrastructure.Community.EctoSocialStore

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

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "timestamp=$time level=$level $metadata message=\"$message\"\n",
  metadata: [:request_id, :user_id, :user_role, :job_id, :oban_job_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason
# Request parameters never logged: keys, and ADR-175 voice clips and transcripts.
config :phoenix, :filter_parameters, ["password", "secret", "api_key", "audio", "transcript"]

config :open_api_spex, :json_render_error_v2, true

# Cache the API spec once; see PaleeWeb.OpenApiSpecCache (ADR-134) for
# why the default adapter exhausts the VM's literal area.
config :open_api_spex, :cache_adapter, PaleeWeb.OpenApiSpecCache

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
