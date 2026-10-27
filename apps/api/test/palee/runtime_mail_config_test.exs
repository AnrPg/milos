defmodule Palee.RuntimeMailConfigTest do
  # Sets process-wide environment variables.
  use ExUnit.Case, async: false

  # 2026-10-27: production STARTTLS to Brevo failed with :tls_failed because
  # OTP verifies peers by default and the mailer gave it no CA certificates or
  # name to check. The prod runtime config must carry both.
  @env %{
    "DATABASE_URL" => "ecto://u:p@localhost/db",
    "MIGRATION_DATABASE_URL" => "ecto://u:p@localhost/db",
    "SECRET_KEY_BASE" => String.duplicate("k", 64),
    "GUARDIAN_SECRET_KEY" => String.duplicate("g", 64),
    "PHX_HOST" => "palee.app",
    "MINIO_ENDPOINT" => "http://minio:9000",
    "MINIO_PUBLIC_ENDPOINT" => "https://media.palee.app",
    "MINIO_ACCESS_KEY" => "a",
    "MINIO_SECRET_KEY" => "s",
    "MEILI_URL" => "http://meili:7700",
    "MEILI_MASTER_KEY" => "m",
    "SMTP_RELAY" => "smtp-relay.brevo.com",
    "MAIL_FROM_ADDRESS" => "no-reply@palee.app",
    "REDIS_URL" => "redis://redis:6379"
  }

  setup do
    previous = Map.new(@env, fn {key, _value} -> {key, System.get_env(key)} end)
    System.put_env(@env)

    on_exit(fn ->
      Enum.each(previous, fn
        {key, nil} -> System.delete_env(key)
        {key, value} -> System.put_env(key, value)
      end)
    end)
  end

  test "the SMTP relay is reached over verified TLS with the relay's own name" do
    config = Config.Reader.read!("config/runtime.exs", env: :prod, target: :host)
    mailer = config[:palee][Palee.Mailer]

    assert mailer[:relay] == "smtp-relay.brevo.com"
    assert mailer[:hostname] == "palee.app"
    assert mailer[:tls] == :always

    tls = mailer[:tls_options]
    assert tls[:verify] == :verify_peer
    assert tls[:server_name_indication] == ~c"smtp-relay.brevo.com"
    assert is_list(tls[:cacerts]) and tls[:cacerts] != []
  end
end
