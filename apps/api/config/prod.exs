import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Req

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

config :milos_training, MilosTrainingWeb.Endpoint,
  force_ssl: [hsts: true, rewrite_on: [:x_forwarded_proto]]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
