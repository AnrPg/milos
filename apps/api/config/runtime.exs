import Config

config :palee, :app_env, config_env()

if System.get_env("PHX_SERVER") do
  config :palee, PaleeWeb.Endpoint, server: true
end

# Outbound Gemini calls honour HTTPS_PROXY (corporate egress, or a sandbox
# proxy that attaches the API key itself), trusting SSL_CERT_FILE when set.
gemini_req_options =
  case System.get_env("HTTPS_PROXY") || System.get_env("https_proxy") do
    proxy when is_binary(proxy) and proxy != "" ->
      %URI{scheme: scheme, host: host, port: port} = URI.parse(proxy)
      cacertfile = System.get_env("SSL_CERT_FILE")

      [
        connect_options:
          [proxy: {String.to_existing_atom(scheme || "http"), host, port, []}] ++
            if(cacertfile, do: [transport_opts: [cacertfile: cacertfile]], else: [])
      ]

    _none ->
      []
  end

# Free-text workout analysis assistant. Without a key the analyze endpoint
# answers 503 and the editor keeps working as a plain text editor.
# ADR-141, ADR-188: geocoding tiers. PHOTON_BASE_URL is our own Photon
# (docs/operations/self-hosted-photon.md; Greece, France, Cyprus), asked
# first and uncapped. PHOTON_FALLBACK_BASE_URL (the public Photon by
# default, "" to turn off) answers for the rest of the world, capped app-wide
# at PHOTON_FALLBACK_MAX_PER_MINUTE (60) as fair use asks. Without our own
# Photon the public one is the only tier, still capped.
public_photon = "https://photon.komoot.io"
photon_base_url = System.get_env("PHOTON_BASE_URL", public_photon)
photon_fallback = System.get_env("PHOTON_FALLBACK_BASE_URL", public_photon)
public_cap = String.to_integer(System.get_env("PHOTON_FALLBACK_MAX_PER_MINUTE", "60"))

photon_cap = fn url ->
  if String.contains?(url, "photon.komoot.io"), do: public_cap, else: nil
end

photon_tiers =
  [photon_base_url, photon_fallback]
  |> Enum.reject(&(&1 == ""))
  |> Enum.uniq()
  |> Enum.map(&[base_url: &1, max_per_minute: photon_cap.(&1)])

config :palee, :photon, base_url: photon_base_url

config :palee, :geocoder_governor,
  backend: Palee.Infrastructure.Facility.PhotonGeocoder,
  tiers: photon_tiers,
  cache_ttl_s: String.to_integer(System.get_env("PHOTON_CACHE_TTL_SECONDS", "86400"))

# ADR-188: the GeoNames dump for the worldwide town list; a mirror may stand in.
config :palee, :geonames,
  base_url: System.get_env("GEONAMES_BASE_URL", "https://download.geonames.org/export/dump")

config :palee, :gemini,
  req_options: gemini_req_options,
  api_key: System.get_env("GEMINI_API_KEY"),
  model: System.get_env("GEMINI_MODEL", "gemini-3.8-flash"),
  # Leave empty for models without thinking levels (e.g. gemini-2.5-*).
  thinking_level: System.get_env("GEMINI_THINKING_LEVEL", "low"),
  parser_thinking_level: System.get_env("GEMINI_PARSER_THINKING_LEVEL", "medium"),
  # Workout library icons (ADR-136) use their own small, cheap model.
  icon_model: System.get_env("GEMINI_ICON_MODEL", "gemini-2.5-flash-lite"),
  # ADR-157: alt text suggestions (vision).
  vision_model: System.get_env("GEMINI_VISION_MODEL", "gemini-2.5-flash-lite"),
  # ADR-175: voice logging speech to text (audio in, transcript out).
  transcribe_model: System.get_env("GEMINI_TRANSCRIBE_MODEL", "gemini-2.5-flash")

# ADR-174: AI scaling suggestions call the Claude API with each gym's own key
# (set in the gym's AI settings); only the default model is configured here.
config :palee, :anthropic,
  req_options: gemini_req_options,
  scaling_model: System.get_env("ANTHROPIC_SCALING_MODEL", "claude-sonnet-5-5"),
  # ADR-175: voice logging turns the transcript into a draft entry.
  voice_model: System.get_env("ANTHROPIC_VOICE_MODEL", "claude-sonnet-5-5")

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

config :palee,
  minio_endpoint: minio_endpoint,
  minio_public_endpoint: minio_public_endpoint,
  minio_access_key: minio_access_key,
  minio_secret_key: minio_secret_key,
  minio_bucket: System.get_env("MINIO_BUCKET", "palee-invoices"),
  minio_avatar_bucket: System.get_env("MINIO_AVATAR_BUCKET", "palee-avatars"),
  minio_media_bucket: System.get_env("MINIO_MEDIA_BUCKET", "palee-media")

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

config :palee, :meilisearch,
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

# ADR-155: Wallet cards. Each platform works only with all of its values set;
# otherwise adding a card answers wallet_not_configured and the rest of
# check-in works. PEM values may be the PEM text or a path to a PEM file.
config :palee, :wallet,
  apple: [
    pass_type_identifier: present_env.("WALLET_APPLE_PASS_TYPE_ID"),
    team_identifier: present_env.("WALLET_APPLE_TEAM_ID"),
    certificate: present_env.("WALLET_APPLE_CERTIFICATE"),
    private_key: present_env.("WALLET_APPLE_PRIVATE_KEY"),
    private_key_password: present_env.("WALLET_APPLE_PRIVATE_KEY_PASSWORD"),
    wwdr_certificate: present_env.("WALLET_APPLE_WWDR_CERTIFICATE"),
    apns_host: present_env.("WALLET_APPLE_APNS_HOST")
  ],
  google: [
    issuer_id: present_env.("WALLET_GOOGLE_ISSUER_ID"),
    service_account_email: present_env.("WALLET_GOOGLE_SERVICE_ACCOUNT_EMAIL"),
    private_key: present_env.("WALLET_GOOGLE_PRIVATE_KEY"),
    origins:
      (present_env.("WALLET_GOOGLE_ORIGINS") || "")
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
  ]

# ADR-171: push to the store apps. FCM (Android) needs the Firebase service
# account JSON (the text or a path); APNs (iOS) needs the team id, the key id
# and the .p8 key (text or path). APNS_TOPIC is the iOS bundle id. Without
# them that provider is off: nothing is registered or sent.
config :palee, :native_push,
  fcm: [service_account: present_env.("FCM_SERVICE_ACCOUNT_JSON")],
  apns: [
    team_id: present_env.("APNS_TEAM_ID"),
    key_id: present_env.("APNS_KEY_ID"),
    private_key: present_env.("APNS_PRIVATE_KEY"),
    topic: present_env.("APNS_TOPIC")
  ]

# ADR-161: Garmin (Health + Activity APIs). Without the client id and
# secret the devices row shows «Σύντομα» and connecting answers
# garmin_not_configured. GARMIN_PUSH_TOKEN, when set, must also appear as
# ?token=… in the push URLs registered at Garmin.
config :palee, :garmin,
  client_id: present_env.("GARMIN_CLIENT_ID"),
  client_secret: present_env.("GARMIN_CLIENT_SECRET"),
  redirect_uri: present_env.("GARMIN_REDIRECT_URI"),
  push_token: present_env.("GARMIN_PUSH_TOKEN")

# ADR-161: the key that encrypts device tokens at rest (32 bytes, base64).
# Without it a key is derived from SECRET_KEY_BASE for this one purpose.
case present_env.("DATA_ENCRYPTION_KEY") do
  nil ->
    :ok

  encoded ->
    case Base.decode64(encoded) do
      {:ok, key} when byte_size(key) == 32 ->
        config :palee, :data_encryption_key, key

      _invalid ->
        raise "DATA_ENCRYPTION_KEY must be 32 bytes, base64-encoded"
    end
end

otel_traces_endpoint = present_env.("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT")
otel_base_endpoint = present_env.("OTEL_EXPORTER_OTLP_ENDPOINT")
otel_endpoint = otel_traces_endpoint || otel_base_endpoint

otel_service_name = present_env.("OTEL_SERVICE_NAME") || "palee-api"

if otel_endpoint do
  config :opentelemetry,
    span_processor: :batch,
    traces_exporter: :otlp,
    resource: [
      service: [
        name: otel_service_name,
        namespace: present_env.("OTEL_SERVICE_NAMESPACE") || "palee"
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

  config :palee, :prometheus_metrics,
    enabled: true,
    port: String.to_integer(metrics_port),
    ip: metrics_ip,
    token: metrics_token
else
  config :palee, :prometheus_metrics, enabled: false
end

if config_env() == :prod do
  guardian_secret_key =
    System.get_env("GUARDIAN_SECRET_KEY") ||
      raise """
      environment variable GUARDIAN_SECRET_KEY is missing.
      Generate a strong secret and set it before starting the server.
      """

  config :palee, Palee.Infrastructure.Auth.Guardian, secret_key: guardian_secret_key

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :palee, Palee.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  config :palee,
    migration_database_url: System.get_env("MIGRATION_DATABASE_URL") || database_url

  redis_url =
    System.get_env("REDIS_URL") ||
      raise """
      environment variable REDIS_URL is missing.
      For example: redis://HOST:6379
      """

  config :palee, :redis_url, redis_url

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :palee, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")
  config :palee, :public_base_url, "https://#{host}"

  smtp_relay = System.get_env("SMTP_RELAY")

  # Mail never falls back to an internal host such as *.4kq.net: with a relay
  # configured, a missing MAIL_FROM_ADDRESS on such a host stops the boot.
  mail_from_address =
    System.get_env("MAIL_FROM_ADDRESS") ||
      if(smtp_relay, do: Palee.Mailer.default_from_address(host), else: "no-reply@#{host}")

  config :palee, :mail_from,
    name: System.get_env("MAIL_FROM_NAME") || "Palee",
    address: mail_from_address,
    reply_to: System.get_env("MAIL_REPLY_TO")

  # ADR-203: the outbox's daily budget. The provider's free plan sends 300 a
  # day; non-security mail stops at the budget (deferred to the next UTC
  # day), security mail at the hard cap.
  config :palee, :email_budget,
    daily_budget: String.to_integer(System.get_env("EMAIL_DAILY_BUDGET") || "280"),
    hard_cap: String.to_integer(System.get_env("EMAIL_DAILY_HARD_CAP") || "295")

  # ADR-212: the shared secret Brevo's transactional webhook presents
  # (bearer token, basic-auth password or x-webhook-secret header). Unset,
  # the webhook refuses every call.
  config :palee, :brevo_webhook_secret, System.get_env("BREVO_WEBHOOK_SECRET")

  # ADR-212: the SMTP key's expiry date (YYYY-MM-DD). A daily check alerts
  # vendors from 30 days before; mail stops when the key expires.
  smtp_key_expires_on =
    case System.get_env("SMTP_KEY_EXPIRES_ON") do
      blank when blank in [nil, ""] ->
        nil

      value ->
        case Date.from_iso8601(String.trim(value)) do
          {:ok, date} ->
            date

          {:error, _} ->
            raise "SMTP_KEY_EXPIRES_ON must be a date like 2027-10-26, got #{inspect(value)}"
        end
    end

  config :palee, :smtp_key_expires_on, smtp_key_expires_on

  # Optional on purpose: absent SMTP_RELAY must not crash boot over a
  # feature (owner-invitation email) the app worked without until now.
  # Falls back to config.exs's Local adapter - dev-mailbox-only, and every
  # caller already treats a delivery failure as a clean {:error, _} rather
  # than crashing (see SendOwnerInvitationEmail.safe_deliver/1) - so this
  # stays a degraded feature, not an outage, until these are set.
  if smtp_relay do
    config :palee, Palee.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_relay,
      # The HELO name; gen_smtp otherwise sends the pod's hostname.
      hostname: System.get_env("SMTP_HELO_HOST") || Palee.Mailer.domain_of(mail_from_address),
      port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      # OTP 26+ verifies TLS peers by default; without CA certificates and the
      # relay's name to check against, STARTTLS failed (:tls_failed). ADR-212:
      # verify_peer against the system CA store (CAStore's bundle if the image
      # has none), SNI and an https-style hostname check on the relay's name.
      tls_options: Palee.Mailer.tls_options(smtp_relay),
      auth: :always,
      ssl: System.get_env("SMTP_SSL") in ~w(true 1)
  end

  config :palee, PaleeWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    check_origin: ["https://#{host}", "http://#{host}"],
    secret_key_base: secret_key_base
end
