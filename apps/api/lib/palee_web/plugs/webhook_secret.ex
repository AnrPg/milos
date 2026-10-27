defmodule PaleeWeb.Plugs.WebhookSecret do
  @moduledoc """
  Admits a provider's webhook only with the shared secret configured under
  `config :palee, <config_key>` (ADR-212; Brevo: `BREVO_WEBHOOK_SECRET`).
  The secret may come as any of:

    * `Authorization: Bearer <secret>` (Brevo's API `auth` option);
    * HTTP basic credentials whose password is the secret (Brevo's
      dashboard: `https://palee:<secret>@palee.app/api/webhooks/brevo`);
    * an `x-webhook-secret: <secret>` header (Brevo's API `headers` option).

  Compared in constant time. Without a configured secret every call is
  refused (503), so an unconfigured server never trusts a webhook.

      plug PaleeWeb.Plugs.WebhookSecret, config_key: :brevo_webhook_secret
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @min_secret_bytes 24

  def init(opts), do: Keyword.fetch!(opts, :config_key)

  def call(conn, config_key) do
    case Application.get_env(:palee, config_key) do
      secret when is_binary(secret) and byte_size(secret) >= @min_secret_bytes ->
        if Enum.any?(presented(conn), &Plug.Crypto.secure_compare(&1, secret)),
          do: conn,
          else: refuse(conn, :unauthorized, "invalid_webhook_secret", "Not authorised")

      _unset ->
        refuse(conn, :service_unavailable, "webhook_not_configured", "Webhook not configured")
    end
  end

  defp presented(conn) do
    authorization =
      conn
      |> get_req_header("authorization")
      |> Enum.flat_map(&from_authorization/1)

    authorization ++ get_req_header(conn, "x-webhook-secret")
  end

  defp from_authorization("Bearer " <> token), do: [String.trim(token)]

  defp from_authorization("Basic " <> encoded) do
    with {:ok, decoded} <- Base.decode64(String.trim(encoded)),
         [_user, password] <- String.split(decoded, ":", parts: 2) do
      [password]
    else
      _invalid -> []
    end
  end

  defp from_authorization(_other), do: []

  defp refuse(conn, status, code, message) do
    :telemetry.execute([:palee, :auth, :anomaly], %{count: 1}, %{
      reason: "webhook_" <> to_string(status)
    })

    conn
    |> put_status(status)
    |> json(%{code: code, error: message})
    |> halt()
  end
end
