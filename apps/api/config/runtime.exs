import Config

config :milos_training, :app_env, config_env()

if System.get_env("PHX_SERVER") do
  config :milos_training, MilosTrainingWeb.Endpoint, server: true
end

# Free-text workout analysis assistant. Without a key the analyze endpoint
# answers 503 and the editor keeps working as a plain text editor.
config :milos_training, :gemini,
  api_key: System.get_env("GEMINI_API_KEY"),
  model: System.get_env("GEMINI_MODEL", "gemini-3.8-flash"),
  # Leave empty for models without thinking levels (e.g. gemini-2.5-*).
  thinking_level: System.get_env("GEMINI_THINKING_LEVEL", "low"),
  parser_thinking_level: System.get_env("GEMINI_PARSER_THINKING_LEVEL", "medium"),
  # Workout library icons (ADR-136) use their own small, cheap model.
  icon_model: System.get_env("GEMINI_ICON_MODEL", "gemini-2.5-flash-lite")

config :web_push_elixir,
  vapid_public_key: System.get_env("WEB_PUSH_PUBLIC_KEY"),
  vapid_private_key: System.get_env("WEB_PUSH_PRIVATE_KEY"),
  vapid_subject: System.get_env("WEB_PUSH_SUBJECT")

minio_endpoint =
  System.get_env("MINIO_ENDPOINT") ||
    if(config_env() == :prod,
      do: raise("MINIO_ENDPOINT is required"),
      else: "http://localhost:9000"
    )

minio_public_endpoint =
  System.get_env("MINIO_PUBLIC_ENDPOINT") ||
    if(config_env() == :prod,
      do: raise("MINIO_PUBLIC_ENDPOINT is required"),
      else: minio_endpoint
    )

minio_access_key =
  System.get_env("MINIO_ACCESS_KEY") ||
    if(config_env() == :prod, do: raise("MINIO_ACCESS_KEY is required"), else: "minioadmin")

minio_secret_key =
  System.get_env("MINIO_SECRET_KEY") ||
    if(config_env() == :prod, do: raise("MINIO_SECRET_KEY is required"), else: "minioadmin")

config :milos_training,
  minio_endpoint: minio_endpoint,
  minio_public_endpoint: minio_public_endpoint,
  minio_access_key: minio_access_key,
  minio_secret_key: minio_secret_key,
  minio_bucket: System.get_env("MINIO_BUCKET", "milos-invoices"),
  minio_avatar_bucket: System.get_env("MINIO_AVATAR_BUCKET", "milos-avatars")

meili_url =
  System.get_env("MEILI_URL") ||
    if(config_env() == :prod,
      do: raise("MEILI_URL is required"),
      else: "http://localhost:7700"
    )

meili_api_key =
  System.get_env("MEILI_MASTER_KEY") ||
    if(config_env() == :prod,
      do: raise("MEILI_MASTER_KEY is required"),
      else: "dev-meili-master-key"
    )

config :milos_training, :meilisearch,
  url: meili_url,
  api_key: meili_api_key,
  admin_member_index: System.get_env("MEILI_ADMIN_MEMBER_INDEX", "admin_members")

# Compose passes optional observability variables through as empty strings
# when they are unset in .env, so blank values must mean "not configured".
present_env = fn name ->
  case System.get_env(name) do
    value when is_binary(value) -> if String.trim(value) == "", do: nil, else: String.trim(value)
    nil -> nil
  end
end

otel_traces_endpoint = present_env.("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
otel_base_endpoint = present_env.("OTEL_EXPORTER_OTLP_ENDPOINT")
otel_endpoint = otel_traces_endpoint || otel_base_endpoint

otel_service_name = present_env.("OTEL_SERVICE_NAME") || "milos-training-api"

if otel_endpoint do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp,
    resource: [
      service: [
        name: otel_service_name,
        namespace: present_env.("OTEL_SERVICE_NAMESPACE") || "milos-training"
      ],
      deployment: [environment: Atom.to_string(config_env())]
    ]

  exporter_config =
    [
      otlp_protocol: :http_protobuf,
      otlp_compression: :gzip,
      otlp_endpoint: otel_base_endpoint || otel_endpoint
    ]

  exporter_config =
    if otel_traces_endpoint do
      Keyword.put(exporter_config, :otlp_traces_endpoint, otel_traces_endpoint)
    else
      exporter_config
    end

  config :opentelemetry_exporter, exporter_config
else
  config :opentelemetry, traces_exporter: :none
end

# Internal Prometheus scrape listener (ADR-116). Disabled unless METRICS_PORT
# is set. It binds its own port, separate from the Phoenix endpoint, which
# Compose never publishes and Caddy never proxies. Production requires a
# bearer token so a misrouted network cannot read operational telemetry.
metrics_port = present_env.("METRICS_PORT")

if metrics_port do
  metrics_token = present_env.("METRICS_TOKEN")

  if config_env() == :prod and (is_nil(metrics_token) or byte_size(metrics_token) < 32) do
    raise "METRICS_TOKEN (at least 32 characters) is required when METRICS_PORT is set"
  end

  {:ok, metrics_ip} =
    "METRICS_BIND_IP"
    |> present_env.()
    |> Kernel.||("0.0.0.0")
    |> String.to_charlist()
    |> :inet.parse_address()

  config :milos_training, :prometheus_metrics,
    enabled: true,
    port: String.to_integer(metrics_port),
    ip: metrics_ip,
    token: metrics_token
else
  config :milos_training, :prometheus_metrics, enabled: false
end

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

  config :milos_training,
    migration_database_url: System.get_env("MIGRATION_DATABASE_URL") || database_url

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
  config :milos_training, :public_base_url, "https://#{host}"

  config :milos_training, :mail_from,
    name: System.get_env("MAIL_FROM_NAME") || "TrainingJournal",
    address: System.get_env("MAIL_FROM_ADDRESS") || "no-reply@#{host}"

  # Optional on purpose: absent SMTP_RELAY must not crash boot over a
  # feature (owner-invitation email) the app worked without until now.
  # Falls back to config.exs's Local adapter - dev-mailbox-only, and every
  # caller already treats a delivery failure as a clean {:error, _} rather
  # than crashing (see SendOwnerInvitationEmail.safe_deliver/1) - so this
  # stays a degraded feature, not an outage, until these are set.
  if smtp_relay = System.get_env("SMTP_RELAY") do
    config :milos_training, MilosTraining.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_relay,
      port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      auth: :always,
      ssl: System.get_env("SMTP_SSL") in ~w(true 1)
  end

  config :milos_training, MilosTrainingWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: ["https://#{host}", "http://#{host}"],
    secret_key_base: secret_key_base
end
