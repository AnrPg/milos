defmodule PaleeWeb.WidgetController do
  @moduledoc """
  Home-screen widgets (ADR-173). The app issues and revokes the widget token
  with its session (`/api/me/widget-tokens`); the widgets themselves call
  `/api/widget/*` with that token (`Plugs.AuthenticateWidget`).
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{WidgetAccess, WidgetSnapshots}
  alias PaleeWeb.Schemas.Widgets, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Widgets"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:create_token,
    summary: "Issue this app install's widget token (replacing its previous one)",
    request_body: S.body(S.token_request()),
    responses: [
      created: {"Widget token", "application/json", S.token_response()},
      unprocessable_entity: {"Unknown platform", "application/json", S.error()}
    ]
  )

  def create_token(conn, _params) do
    with {:ok, token} <- WidgetAccess.issue(conn.assigns.user_context, conn.body_params) do
      conn |> put_status(:created) |> json(token)
    end
  end

  operation(:delete_token,
    summary: "Revoke a widget token (sign-out on that install)",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      no_content: "Revoked",
      not_found: {"No such token", "application/json", S.error()}
    ]
  )

  def delete_token(conn, %{id: id}) do
    with :ok <- WidgetAccess.revoke(conn.assigns.user_context, id),
         do: send_resp(conn, :no_content, "")
  end

  @timezone %Parameter{
    name: :timezone,
    in: :query,
    required: false,
    description: "The phone's IANA zone (UTC by default)",
    schema: %Schema{type: :string}
  }

  operation(:snapshot,
    summary: "What the widgets show now (widget token)",
    parameters: [@timezone],
    responses: [
      ok: {"Snapshot", "application/json", S.snapshot_response()},
      unauthorized: {"Revoked or expired widget token", "application/json", S.error()}
    ]
  )

  def snapshot(conn, params) do
    with {:ok, snapshot} <- WidgetSnapshots.show(conn.assigns.user_context, params),
         do: json(conn, snapshot)
  end

  operation(:add_water,
    summary: "«+1 νερό» from the widget: one glass of the member's size (widget token)",
    request_body: S.body(S.water_request()),
    responses: [
      ok: {"Snapshot", "application/json", S.snapshot_response()},
      unauthorized: {"Revoked or expired widget token", "application/json", S.error()},
      forbidden: {"Health-data consent needed (open the app)", "application/json", S.error()}
    ]
  )

  def add_water(conn, _params) do
    with {:ok, snapshot} <-
           WidgetSnapshots.add_water(conn.assigns.user_context, conn.body_params),
         do: json(conn, snapshot)
  end
end
