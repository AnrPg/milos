defmodule PaleeWeb.GarminIntegrationController do
  @moduledoc """
  Garmin's side of the integration (ADR-161): the OAuth return (a browser
  redirect, so no bearer token: the `state` names the sign-in), and the push
  and deregistration endpoints Garmin calls. Pushes are verified, answered
  at once and imported in the background.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  require Logger

  alias Palee.Application.{GarminConnection, GarminPush, PublicURL}
  alias PaleeWeb.Schemas.Devices, as: S
  alias OpenApiSpex.{Parameter, Schema}

  tags(["Connected devices"])

  operation(:callback,
    summary: "Garmin's OAuth return; redirects to the devices page",
    parameters: [
      %Parameter{name: :code, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :state, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :error, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    responses: [found: {"Back to Συνδεδεμένες συσκευές", "text/html", %Schema{type: :string}}]
  )

  def callback(conn, params) do
    query =
      case GarminConnection.complete(params) do
        {:ok, :connected} -> %{"garmin" => "connected"}
        {:error, reason} -> %{"garmin" => "error", "reason" => to_string(reason)}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> redirect(external: PublicURL.base_url() <> "/me/devices?" <> URI.encode_query(query))
  end

  operation(:push,
    summary: "Garmin's push endpoint (summaries or callback URLs); verified, idempotent",
    parameters: [
      %Parameter{name: :token, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    request_body: S.body(%Schema{type: :object, additionalProperties: true}),
    responses: [
      ok: {"Accepted", "application/json", S.push_response()},
      unauthorized: {"Not from Garmin for this app", "application/json", S.error()},
      service_unavailable: {"Garmin isn't configured here", "application/json", S.error()}
    ]
  )

  def push(conn, params) do
    conn
    |> respond(GarminPush.accept(conn.body_params, verification(conn, params)))
  end

  operation(:deregistration,
    summary: "Garmin tells Palee a person removed the app at Garmin",
    parameters: [
      %Parameter{name: :token, in: :query, required: false, schema: %Schema{type: :string}}
    ],
    request_body: S.body(%Schema{type: :object, additionalProperties: true}),
    responses: [
      ok: {"Accepted", "application/json", S.push_response()},
      unauthorized: {"Not from Garmin for this app", "application/json", S.error()}
    ]
  )

  def deregistration(conn, params) do
    conn
    |> respond(GarminPush.deregister(conn.body_params, verification(conn, params)))
  end

  defp respond(conn, {:ok, result}), do: json(conn, result)

  defp respond(conn, {:error, :garmin_not_configured}) do
    conn
    |> put_status(:service_unavailable)
    |> json(%{code: "garmin_not_configured", error: "Garmin isn't available on this server"})
  end

  defp respond(conn, {:error, reason}) do
    Logger.warning("garmin push refused #{inspect(reason)}")

    conn
    |> put_status(:unauthorized)
    |> json(%{code: "invalid_push", error: "Not a Garmin push for this app"})
  end

  defp verification(conn, params) do
    %{
      client_id: conn |> get_req_header("garmin-client-id") |> List.first(),
      token: Map.get(params, "token")
    }
  end
end
