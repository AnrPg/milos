defmodule PaleeWeb.PaymentWebhookController do
  @moduledoc """
  ADR-246: notifications from a business's payment provider. Nothing in
  them is trusted: each names a payment that is then read back from the
  provider. `GET` answers Viva's check of a new webhook URL.
  """

  use PaleeWeb, :controller

  alias Palee.Application.Payments.Webhooks
  alias PaleeWeb.Plugs.CacheRawBody

  def show(conn, %{"organization_id" => organization_id, "account_id" => account_id}),
    do: handle(conn, organization_id, account_id, "GET", "")

  def create(conn, %{"organization_id" => organization_id, "account_id" => account_id}) do
    {body, conn} =
      case CacheRawBody.raw_body(conn) do
        "" ->
          case Plug.Conn.read_body(conn, length: 1_000_000) do
            {:ok, body, conn} -> {body, conn}
            _other -> {"", conn}
          end

        body ->
          {body, conn}
      end

    handle(conn, organization_id, account_id, "POST", body)
  end

  defp handle(conn, organization_id, account_id, method, body) do
    request = %{method: method, headers: conn.req_headers, body: body}

    case Webhooks.handle(organization_id, account_id, request) do
      {:ok, _count} ->
        json(conn, %{ok: true})

      {:reply, status, reply} ->
        conn |> put_status(status) |> json(reply)

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{code: "not_found"})

      {:error, :invalid_signature} ->
        conn |> put_status(:bad_request) |> json(%{code: "invalid_signature"})

      {:error, :invalid_payload} ->
        conn |> put_status(:bad_request) |> json(%{code: "invalid_payload"})

      # The provider retries later.
      {:error, _reason} ->
        conn |> put_status(:service_unavailable) |> json(%{code: "unavailable"})
    end
  end
end
