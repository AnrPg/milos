# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :elixir, :time_zone_database, Tz.TimeZoneDatabase

config :milos_training,
  ecto_repos: [MilosTraining.Repo],
  generators: [timestamp_type: :utc_datetime],
  env: config_env()

config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :none

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_compression: :gzip

config :milos_training, Oban,
  repo: MilosTraining.Repo,
  plugins: [
    {Oban.Plugins.Cron,
     crontab: [
       {"*/15 * * * *", MilosTraining.Workers.RefreshLeaderboardJob},
       {"*/15 * * * *", MilosTraining.Workers.RefreshFinanceAggregatesJob},
       {"*/15 * * * *", MilosTraining.Workers.RefreshCoachingAggregatesJob},
       {"0 2 * * *", MilosTraining.Workers.MarkOverdueInvoicesJob},
       {"17 * * * *", MilosTraining.Workers.ReconcileEntitlementReservationsJob},
       {"0 9 * * *", MilosTraining.Workers.PaymentReminderJob},
       {"41 * * * *", MilosTraining.Workers.ExecutionAbandonmentSweepJob},
       {"*/30 * * * *", MilosTraining.Workers.RebuildMemberSearchIndexJob},
       {"0 8 * * *", MilosTraining.Workers.PackageExpiryReminderJob},
       {"23 * * * *", MilosTraining.Workers.CoachingReplyOverdueJob},
       {"41 6 * * *", MilosTraining.Workers.CorporateInvoicingJob},
       {"7 7 * * *", MilosTraining.Workers.InventoryDigestJob},
       {"30 8 * * *", MilosTraining.Workers.SubscriptionExpiryJob},
       {"13 * * * *", MilosTraining.Workers.ProvisionGymClubsJob},
       {"52 * * * *", MilosTraining.Workers.SweepOrphanMediaJob},
       {"37 3 * * *", MilosTraining.Workers.SweepOrphanMediaJob, args: %{"dangling" => true}},
       {"20 4 * * *", MilosTraining.Workers.ArchiveQuietGroupsJob},
       {"*/10 * * * *", MilosTraining.Workers.EventRemindersJob},
       {"0 7 * * *", MilosTraining.Workers.AroundAlertsJob},
       {"30 9 * * *", MilosTraining.Workers.BodyRemindersJob},
       {"0,30 * * * *", MilosTraining.Workers.BuddyWeeklySummaryJob},
       {"*/10 * * * *", MilosTraining.Workers.WellnessNudgesJob}
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

config :milos_training, MilosTraining.Infrastructure.Auth.Guardian,
  issuer: {MilosTraining.Infrastructure.Auth.Guardian, :fetch_issuer, []},
  secret_key: {MilosTraining.Infrastructure.Auth.Guardian, :fetch_secret, []},
  token_ttl: %{"access" => {15, :minutes}, "refresh" => {30, :days}}

config :milos_training,
       :workout_icon_suggester,
       MilosTraining.Infrastructure.Ai.GeminiWorkoutIconSuggester

config :milos_training, :geocoder, MilosTraining.Infrastructure.Facility.PhotonGeocoder

config :milos_training,
       :map_link_resolver,
       MilosTraining.Infrastructure.Facility.HttpMapLinkResolver

config :milos_training, :start_redix, true
config :milos_training, :start_oban, true
# ADR-123: a started execution not completed within this many hours is recorded
# as workout_execution_abandoned by ExecutionAbandonmentSweepJob.
config :milos_training, :execution_abandonment_hours, 6
config :milos_training, :redis_url, System.get_env("REDIS_URL", "redis://localhost:6379")
config :milos_training, :readiness_checker, MilosTraining.Infrastructure.Readiness.Live
config :milos_training, :identity_user_store, MilosTraining.Infrastructure.Identity.EctoUserStore

config :milos_training,
       :organization_store,
       MilosTraining.Infrastructure.Organizations.EctoOrganizationStore

config :milos_training, :coaching_store, MilosTraining.Infrastructure.Coaching.EctoCoachingStore

config :milos_training,
       :facility_store,
       MilosTraining.Infrastructure.Facility.EctoFacilityStore

config :milos_training, :content_store, MilosTraining.Infrastructure.Content.EctoContentStore

config :milos_training,
       :appointment_store,
       MilosTraining.Infrastructure.Appointments.EctoAppointmentStore

config :milos_training,
       :coaching_form_review_store,
       MilosTraining.Infrastructure.Coaching.EctoFormReviewStore

config :milos_training,
       :housekeeping_store,
       MilosTraining.Infrastructure.Housekeeping.EctoHousekeepingStore

config :milos_training,
       :inventory_store,
       MilosTraining.Infrastructure.Inventory.EctoInventoryStore

config :milos_training,
       :community_store,
       MilosTraining.Infrastructure.Community.EctoCommunityStore

config :milos_training,
       :community_social_store,
       MilosTraining.Infrastructure.Community.EctoSocialStore

config :milos_training,
       :community_event_store,
       MilosTraining.Infrastructure.Community.EctoEventStore

config :milos_training,
       :event_payments,
       MilosTraining.Infrastructure.Finance.FinanceEventPayments

config :milos_training, :trial_store, MilosTraining.Infrastructure.Trials.EctoTrialStore
config :milos_training, :trial_scheduler, MilosTraining.Infrastructure.Trials.ObanTrialScheduler

# ADR-144: reactions to facts other contexts announce (MilosTraining.DomainEvents).
config :milos_training, :domain_event_handlers, %{
  membership_activated: [
    MilosTraining.Application.TrialReactions,
    MilosTraining.Application.EventReactions
  ],
  attendance_recorded: [
    MilosTraining.Application.TrialReactions,
    MilosTraining.Application.WalletReactions
  ],
  booking_cancelled: [
    MilosTraining.Application.TrialReactions,
    MilosTraining.Application.WalletReactions
  ],
  booking_made: [MilosTraining.Application.WalletReactions],
  class_cancelled: [MilosTraining.Application.TrialReactions]
}

config :milos_training,
       :saved_filter_store,
       MilosTraining.Infrastructure.Identity.EctoSavedFilterStore

config :milos_training, :media_store, MilosTraining.Infrastructure.Media.EctoMediaStore

# ADR-157: post photos and videos. ImageMagick and ffmpeg ship in the API
# image; alt text suggestions use Gemini when configured.
config :milos_training,
       :image_processor,
       MilosTraining.Infrastructure.Media.ImageMagickProcessor

config :milos_training, :video_transcoder, MilosTraining.Infrastructure.Media.FfmpegTranscoder
config :milos_training, :image_describer, MilosTraining.Infrastructure.Ai.GeminiImageDescriber

# ADR-154: Γύρω μου.
config :milos_training,
       :discovery_store,
       MilosTraining.Infrastructure.Places.EctoDiscoveryStore

config :milos_training, :gazetteer_store, MilosTraining.Infrastructure.Places.EctoGazetteerStore
config :milos_training, :home_area_store, MilosTraining.Infrastructure.Places.EctoHomeAreaStore

config :milos_training,
       :public_profile_store,
       MilosTraining.Infrastructure.Organizations.EctoPublicProfileStore

config :milos_training,
       :coaching_note_store,
       MilosTraining.Infrastructure.Coaching.EctoNoteStore

config :milos_training,
       :coaching_relationship_store,
       MilosTraining.Infrastructure.Coaching.EctoRelationshipStore

config :milos_training,
       :ai_usage_store,
       MilosTraining.Infrastructure.AiUsage.EctoAiUsageStore

config :milos_training,
       :nutrition_store,
       MilosTraining.Infrastructure.Nutrition.EctoNutritionStore

config :milos_training,
       :execution_store,
       MilosTraining.Infrastructure.Execution.EctoExecutionStore

config :milos_training,
       :class_timer_store,
       MilosTraining.Infrastructure.Execution.EctoClassTimerStore

config :milos_training,
       :training_log_store,
       MilosTraining.Infrastructure.Execution.EctoTrainingLogStore

config :milos_training, :finance_store, MilosTraining.Infrastructure.Finance.EctoFinanceStore

config :milos_training,
       :finance_accounting_store,
       MilosTraining.Infrastructure.Finance.EctoFinanceAccountingStore

config :milos_training, :workout_store, MilosTraining.Infrastructure.Workouts.EctoWorkoutStore

config :milos_training,
       :workout_text_analyzer,
       MilosTraining.Infrastructure.Workouts.GeminiWorkoutTextAnalyzer

config :milos_training,
       :gamification_store,
       MilosTraining.Infrastructure.Gamification.EctoGamificationStore

config :milos_training,
       :scheduling_store,
       MilosTraining.Infrastructure.Scheduling.EctoSchedulingStore

config :milos_training, :pr_store, MilosTraining.Infrastructure.Pantheon.EctoPRStore
config :milos_training, :journal_store, MilosTraining.Infrastructure.Journal.EctoJournalStore
config :milos_training, :body_store, MilosTraining.Infrastructure.Body.EctoBodyStore
config :milos_training, :buddy_store, MilosTraining.Infrastructure.Buddies.EctoBuddyStore

config :milos_training,
       :support_scheduler,
       MilosTraining.Infrastructure.Buddies.ObanSupportScheduler

# ADR-160: «Χρειάζομαι στήριξη» from Λιγούρα (the port M11 calls).
config :milos_training, :support_requests, MilosTraining.Application.SupportRequests

config :milos_training,
       :push_subscription_store,
       MilosTraining.Infrastructure.Notifications.EctoPushSubscriptionStore

config :milos_training,
       :notification_store,
       MilosTraining.Infrastructure.Notifications.EctoNotificationStore

config :milos_training, :feedback_store, MilosTraining.Infrastructure.Feedback.EctoFeedbackStore

config :milos_training,
       :wellbeing_store,
       MilosTraining.Infrastructure.Wellbeing.EctoWellbeingStore

config :milos_training,
       :wellness_store,
       MilosTraining.Infrastructure.Wellness.EctoWellnessStore

config :milos_training,
       :messaging_thread_store,
       MilosTraining.Infrastructure.Messaging.EctoThreadStore

config :milos_training,
       :messaging_message_store,
       MilosTraining.Infrastructure.Messaging.EctoMessageStore

config :milos_training, :avatar_storage, MilosTraining.Infrastructure.Storage.MinioStorage
config :milos_training, :document_storage, MilosTraining.Infrastructure.Storage.MinioStorage
config :milos_training, :tenant_object_store, MilosTraining.Infrastructure.Storage.MinioStorage
config :milos_training, :landing_cache, MilosTraining.Infrastructure.Cache.LandingCache

config :milos_training,
       :pr_search_index,
       MilosTraining.Infrastructure.Search.MeilisearchPRIndex

config :milos_training,
       :signed_token,
       MilosTraining.Infrastructure.Security.PhoenixSignedToken

config :milos_training, :public_base_url, "http://localhost:4000"

# ADR-155: Wallet cards. Credentials come from runtime config (runtime.exs);
# without them each platform reports wallet_not_configured.
config :milos_training, :wallet_store, MilosTraining.Infrastructure.Wallet.EctoWalletStore

config :milos_training, :wallet_pass_builders, %{
  apple: MilosTraining.Infrastructure.Wallet.ApplePassBuilder,
  google: MilosTraining.Infrastructure.Wallet.GooglePassBuilder
}

config :milos_training, :wallet_pass_updaters, %{
  apple: MilosTraining.Infrastructure.Wallet.ApnsPassUpdater,
  google: MilosTraining.Infrastructure.Wallet.GoogleWalletUpdater
}

config :milos_training,
       :wallet_image_source,
       MilosTraining.Infrastructure.Wallet.HttpImageSource

# ADR-155: door codes, member codes and Wallet barcodes.
config :milos_training,
       :key_derivation,
       MilosTraining.Infrastructure.Security.PhoenixKeyDerivation

config :milos_training,
       :realtime_publisher,
       MilosTraining.Infrastructure.Realtime.PhoenixRealtimePublisher

config :milos_training,
       :admin_member_search_index,
       MilosTraining.Infrastructure.Search.MeilisearchMemberIndex

config :milos_training,
       :identity_password_hasher,
       MilosTraining.Infrastructure.Auth.PasswordHasher

config :milos_training, :rate_limiter, MilosTraining.Infrastructure.Security.RedisRateLimiter
config :milos_training, :token_store, MilosTraining.Infrastructure.Security.RedisTokenStore
config :milos_training, :token_issuer, MilosTraining.Infrastructure.Auth.GuardianTokenIssuer
config :milos_training, :token_verifier, MilosTraining.Infrastructure.Auth.GuardianTokenVerifier
config :milos_training, :password_verifier, MilosTraining.Infrastructure.Auth.Password

config :milos_training,
       :remote_ip,
       headers: ["x-forwarded-for"],
       proxies: [{127, 0, 0, 1}, {10, 0, 0, 0, 8}, {172, 16, 0, 0, 12}, {192, 168, 0, 0, 16}]

# Configures the endpoint
config :milos_training, MilosTrainingWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: MilosTrainingWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: MilosTraining.PubSub,
  live_view: [signing_salt: "aRnuRHSQ"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :milos_training, MilosTraining.Mailer, adapter: Swoosh.Adapters.Local

# Overridden for prod in runtime.exs (MAIL_FROM_NAME/MAIL_FROM_ADDRESS); this
# default is fine for dev/test, where mail never actually leaves the box.
config :milos_training, :mail_from, name: "TrainingJournal", address: "no-reply@example.com"

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "timestamp=$time level=$level $metadata message=\"$message\"\n",
  metadata: [:request_id, :user_id, :user_role, :job_id, :oban_job_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :open_api_spex, :json_render_error_v2, true

# Cache the API spec once; see MilosTrainingWeb.OpenApiSpecCache (ADR-134) for
# why the default adapter exhausts the VM's literal area.
config :open_api_spex, :cache_adapter, MilosTrainingWeb.OpenApiSpecCache

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
