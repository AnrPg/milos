# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

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
       {"0 9 * * *", MilosTraining.Workers.PaymentReminderJob}
     ]}
  ],
  queues: [
    default: 10,
    notifications: 20,
    gamification: 5,
    analytics: 3
  ]

config :milos_training, MilosTraining.Infrastructure.Auth.Guardian,
  issuer: {MilosTraining.Infrastructure.Auth.Guardian, :fetch_issuer, []},
  secret_key: {MilosTraining.Infrastructure.Auth.Guardian, :fetch_secret, []},
  token_ttl: %{"access" => {15, :minutes}, "refresh" => {30, :days}}

config :milos_training, :start_redix, true
config :milos_training, :start_oban, true
config :milos_training, :redis_url, System.get_env("REDIS_URL", "redis://localhost:6379")
config :milos_training, :readiness_checker, MilosTraining.Infrastructure.Readiness.Live
config :milos_training, :identity_user_store, MilosTraining.Infrastructure.Identity.EctoUserStore
config :milos_training, :coaching_store, MilosTraining.Infrastructure.Coaching.EctoCoachingStore

config :milos_training,
       :execution_store,
       MilosTraining.Infrastructure.Execution.EctoExecutionStore

config :milos_training, :finance_store, MilosTraining.Infrastructure.Finance.EctoFinanceStore
config :milos_training, :workout_store, MilosTraining.Infrastructure.Workouts.EctoWorkoutStore

config :milos_training,
       :gamification_store,
       MilosTraining.Infrastructure.Gamification.EctoGamificationStore

config :milos_training,
       :scheduling_store,
       MilosTraining.Infrastructure.Scheduling.EctoSchedulingStore

config :milos_training, :pr_store, MilosTraining.Infrastructure.Pantheon.EctoPRStore

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
       :messaging_thread_store,
       MilosTraining.Infrastructure.Messaging.EctoThreadStore

config :milos_training,
       :messaging_message_store,
       MilosTraining.Infrastructure.Messaging.EctoMessageStore

config :milos_training, :avatar_storage, MilosTraining.Infrastructure.Storage.MinioStorage
config :milos_training, :document_storage, MilosTraining.Infrastructure.Storage.MinioStorage
config :milos_training, :landing_cache, MilosTraining.Infrastructure.Cache.LandingCache

config :milos_training,
       :pr_search_index,
       MilosTraining.Infrastructure.Search.MeilisearchPRIndex

config :milos_training,
       :signed_token,
       MilosTraining.Infrastructure.Security.PhoenixSignedToken

config :milos_training, :public_base_url, "http://localhost:4000"

config :milos_training,
       :realtime_publisher,
       MilosTraining.Infrastructure.Realtime.PhoenixRealtimePublisher

config :milos_training,
       :admin_member_search_index,
       MilosTraining.Infrastructure.Search.MeilisearchMemberIndex

config :milos_training, :meilisearch,
  url: System.get_env("MEILI_URL", "http://localhost:7700"),
  api_key: System.get_env("MEILI_MASTER_KEY", "dev-meili-master-key"),
  admin_member_index: System.get_env("MEILI_ADMIN_MEMBER_INDEX", "admin_members")

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

# Configures Elixir's Logger
config :logger, :default_formatter,
  format: "timestamp=$time level=$level $metadata message=\"$message\"\n",
  metadata: [:request_id, :user_id, :user_role, :job_id, :oban_job_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :open_api_spex, :json_render_error_v2, true

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
