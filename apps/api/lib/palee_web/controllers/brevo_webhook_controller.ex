defmodule PaleeWeb.BrevoWebhookController do
  @moduledoc """
  Brevo's transactional webhook (ADR-212): bounces, complaints, blocks,
  unsubscribes and deliveries of the mail Palee sent. Authenticated by the
  shared secret (`PaleeWeb.Plugs.WebhookSecret`); the events are applied by
  `Palee.Email.handle_provider_events/3`, idempotently, so Brevo may retry.
  Not part of the app's OpenAPI contract: only Brevo calls it.
  """

  use PaleeWeb, :controller

  def create(conn, _params) do
    case Palee.Email.handle_provider_events(:brevo, conn.body_params) do
      {:ok, counts} ->
        json(conn, counts)

      {:error, :invalid_payload} ->
        conn
        |> put_status(:bad_request)
        |> json(%{code: "invalid_payload", error: "Not a Brevo webhook event"})
    end
  end
end
