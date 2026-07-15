import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :milos_training, MilosTraining.Repo,
  username: System.get_env("DB_USER", "postgres"),
  password: System.get_env("DB_PASSWORD", "postgres"),
  hostname: System.get_env("DB_HOST", "localhost"),
  port: String.to_integer(System.get_env("DB_PORT", "5432")),
  database:
    System.get_env("DB_NAME", "milos_training_test#{System.get_env("MIX_TEST_PARTITION")}"),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2,
  queue_target: 5_000,
  queue_interval: 5_000

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :milos_training, MilosTrainingWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "9g/uPwNR7BtXjTmOMhZcQ9lYkvib61Pf0vXOwL0l1B+quNOdeELOzmLPtzO0kwTU",
  server: false

# In test we don't send emails
config :milos_training, MilosTraining.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

config :milos_training, :start_redix, false
config :milos_training, :start_oban, false
config :milos_training, :rate_limiter, MilosTraining.Infrastructure.Security.MemoryRateLimiter
config :milos_training, :token_store, MilosTraining.Infrastructure.Security.MemoryTokenStore
config :milos_training, :token_issuer, MilosTraining.Infrastructure.Auth.GuardianTokenIssuer
config :milos_training, :token_verifier, MilosTraining.Infrastructure.Auth.GuardianTokenVerifier
config :milos_training, :password_verifier, MilosTraining.Infrastructure.Auth.Password

config :milos_training, :meilisearch,
  url: System.get_env("MEILI_URL", "http://localhost:7700"),
  api_key: System.get_env("MEILI_MASTER_KEY", "dev-meili-master-key"),
  admin_member_index: System.get_env("MEILI_ADMIN_MEMBER_INDEX", "admin_members"),
  log_failures: false
