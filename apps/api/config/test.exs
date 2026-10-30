import Config

# ADR-190: the mock card provider simulates success and failure in tests.
config :palee, Palee.Infrastructure.Shop.MockPaymentProvider, mode: :simulate

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
#
# The tests connect as a login role that owns the database but is not a
# superuser, as production's migration role does, so a migration or query
# that only a superuser may run fails here and not at the deploy.
# `mix palee.test.migrate` (run by `mix test`) provisions it with the admin
# credentials below, which also serve RLSCase's role setup.
config :palee, :test_database_admin,
  username: System.get_env("DB_ADMIN_USER") || System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_ADMIN_PASSWORD") || System.get_env("DB_PASSWORD", "postgres")

config :palee, Palee.Repo,
  username: "palee_test_owner",
  password: "palee_test_owner_pw",
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  database: System.get_env("DB_NAME", "palee_test#{System.get_env("MIX_TEST_PARTITION")}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5_000,
  queue_interval: 5_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :palee, PaleeWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9g/uPwNR7BtXjTmOMhZcQ9lYkvib61Pf0vXOwL0l1B+quNOdeELOzmLPtzO0kwTU",
  server: false

# In test we don't send emails
config :palee, Palee.Mailer, adapter: Swoosh.Adapters.Test

# ADR-203: the outbox stores rows and their DeliverEmailJob in the sandbox
# (Oban is not started, so nothing is sent until a test asks).
# `Palee.EmailCase` asserts on what was enqueued and delivers it through
# the Swoosh test adapter; no test trips the budget unless it lowers it.
config :palee, :email_budget, daily_budget: 100_000, hard_cap: 100_000
config :palee, :email_templates_extra, %{sample_notice: Palee.TestSupport.SampleEmail}

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :palee, :start_redix, false
config :palee, :start_oban, false
config :palee, :workout_icon_suggester, Palee.FakeWorkoutIconSuggester
config :palee, :scaling_advisor, Palee.FakeScalingAdvisor
config :palee, :speech_transcriber, Palee.FakeSpeechTranscriber
config :palee, :log_draft_parser, Palee.FakeLogDraftParser

# ADR-157: deterministic media adapters; tests tagged :imagemagick / :ffmpeg
# drive the real ones when the tools are installed.
config :palee, :image_processor, Palee.FakeImageProcessor
config :palee, :video_transcoder, Palee.FakeVideoTranscoder
config :palee, :image_describer, Palee.FakeImageDescriber
config :palee, :geocoder, Palee.FakeGeocoder
config :palee, :world_gazetteer_source, Palee.FakeWorldGazetteerSource
config :palee, :map_link_resolver, Palee.FakeMapLinkResolver
config :palee, :start_storage_reconciler, false
config :palee, :rate_limiter, Palee.Infrastructure.Security.MemoryRateLimiter
config :palee, :token_store, Palee.Infrastructure.Security.MemoryTokenStore
config :palee, :token_issuer, Palee.Infrastructure.Auth.GuardianTokenIssuer
config :palee, :token_verifier, Palee.Infrastructure.Auth.GuardianTokenVerifier
config :palee, :password_verifier, Palee.Infrastructure.Auth.Password

config :palee, :meilisearch,
  url: System.get_env("MEILI_URL", "http://localhost:7700"),
  api_key: System.get_env("MEILI_MASTER_KEY", "dev-meili-master-key"),
  admin_member_index: System.get_env("MEILI_ADMIN_MEMBER_INDEX", "admin_members"),
  log_failures: false

# ADR-117: tenant export/purge object operations run against an in-memory store.
config :palee, :tenant_object_store, Palee.TestSupport.MemoryObjectStore
config :palee, :workout_text_analyzer, Palee.Test.FakeWorkoutTextAnalyzer

# ADR-155: Wallet platforms are told about changes through recording fakes;
# a box logo is never fetched.
config :palee, :wallet_pass_updaters, %{
  apple: Palee.FakeWalletUpdater,
  google: Palee.FakeWalletUpdater
}

config :palee, :wallet_image_source, Palee.FakeWalletImageSource

# ADR-171: native push goes to recording fakes; tests switch providers on.
config :palee, :native_push_senders, %{
  fcm: Palee.FakeNativePushSender.Fcm,
  apns: Palee.FakeNativePushSender.Apns
}

# ADR-161: Garmin is faked; tests turn it on and script its answers.
config :palee, :garmin_client, Palee.FakeGarminClient

# ADR-242: a fixed test key for the fiscal journal (never used outside tests).
config :palee, Palee.Infrastructure.Fiscal.Ed25519JournalSigner,
  signing_key: "test-1:" <> Base.encode64(:binary.copy(<<7>>, 32))

# ADR-246: the sandbox payment provider and stubbed provider HTTP in tests.
config :palee, :payments_sandbox, true

config :palee, :stripe_connect, %{
  "test" => %{client_id: "ca_test_platform", secret_key: "sk_test_platform"}
}

config :palee, :payments_http, req_options: [plug: {Req.Test, Palee.PaymentsHttp}]
# ADR-250/251/266: fiskaly calls go to a test plug.
config :palee, :fiscal_http, req_options: [plug: {Req.Test, Palee.FiscalHttp}]
# ADR-273: myDATA (saving a test or production connection checks it) too.
config :palee, :mydata, req_options: [plug: {Req.Test, Palee.FiscalHttp}, retry: false]
