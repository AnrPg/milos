import Config

if System.get_env("PHX_SERVER") do
  config :milos_training, MilosTrainingWeb.Endpoint, server: true
end

config :web_push_elixir,
  vapid_public_key: System.get_env("WEB_PUSH_PUBLIC_KEY"),
  vapid_private_key: System.get_env("WEB_PUSH_PRIVATE_KEY"),
  vapid_subject: System.get_env("WEB_PUSH_SUBJECT")

config :milos_training,
  minio_endpoint: System.get_env("MINIO_ENDPOINT", "http://localhost:9000"),
  minio_access_key: System.get_env("MINIO_ACCESS_KEY", "minioadmin"),
  minio_secret_key: System.get_env("MINIO_SECRET_KEY", "minioadmin"),
  minio_bucket: System.get_env("MINIO_BUCKET", "milos-invoices")

if config_env() == :prod do
  guardian_secret_key =
    System.get_env("GUARDIAN_SECRET_KEY") ||
      raise """
      environment variable GUARDIAN_SECRET_KEY is missing.
      Generate a strong secret and set it before starting the server.
      """

  config :milos_training, MilosTraining.Infrastructure.Auth.Guardian,
    secret_key: guardian_secret_key

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :milos_training, MilosTraining.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  redis_url =
    System.get_env("REDIS_URL") ||
      raise """
      environment variable REDIS_URL is missing.
      For example: redis://HOST:6379
      """

  config :milos_training, :redis_url, redis_url

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :milos_training, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :milos_training, MilosTrainingWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: ["https://#{host}", "http://#{host}"],
    secret_key_base: secret_key_base
end
