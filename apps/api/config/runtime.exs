import Config

if System.get_env("PHX_SERVER") do
  config :milos_training, MilosTrainingWeb.Endpoint, server: true
end

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

otel_traces_endpoint = System.get_env("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
otel_endpoint = otel_traces_endpoint || System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

otel_service_name = System.get_env("OTEL_SERVICE_NAME", "milos-training-api")

if otel_endpoint do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp,
    resource: [
      service: [
        name: otel_service_name,
        namespace: System.get_env("OTEL_SERVICE_NAMESPACE", "milos-training")
      ],
      deployment: [environment: Atom.to_string(config_env())]
    ]

  exporter_config =
    [
      otlp_protocol: :http_protobuf,
      otlp_compression: :gzip,
      otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", otel_endpoint)
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
  config :milos_training, :public_base_url, "https://#{host}"

  config :milos_training, MilosTrainingWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: ["https://#{host}", "http://#{host}"],
    secret_key_base: secret_key_base
end
