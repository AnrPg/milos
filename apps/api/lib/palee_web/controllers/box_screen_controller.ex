defmodule PaleeWeb.BoxScreenController do
  @moduledoc """
  The box screen itself (ADR-253): pairing with a code, then the day it
  shows and its class timers, with the display token
  (`Plugs.AuthenticateBoxScreen`). The realtime part is
  `/box_screen_socket`.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias OpenApiSpex.Parameter
  alias Palee.Application.BoxScreens.BoxScreenDisplay
  alias PaleeWeb.ClassTimerController
  alias PaleeWeb.Schemas.BoxScreens, as: S

  action_fallback PaleeWeb.FallbackController

  tags(["Box screens"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:pair,
    summary: "Pair this TV with the code staff got (no sign-in)",
    description:
      "Case, spaces and dashes do not matter. A code pairs one device once. The display " <>
        "token lasts 90 days and is renewed with `POST /api/box-screen/token`.",
    security: [],
    request_body: S.body(S.pair_request()),
    responses: [
      created: {"Display token", "application/json", S.pair_response()},
      unprocessable_entity: {"Wrong or expired code", "application/json", S.error()}
    ]
  )

  def pair(conn, _params) do
    with {:ok, result} <- BoxScreenDisplay.pair(conn.body_params) do
      conn |> put_status(:created) |> json(result)
    end
  end

  operation(:today,
    summary: "What the screen shows today: classes, WODs, leaderboards and the focus",
    responses: [
      ok: {"Today", "application/json", S.today()},
      unauthorized: {"Invalid display token", "application/json", S.error()}
    ]
  )

  def today(conn, _params) do
    with {:ok, today} <- BoxScreenDisplay.today(conn.assigns.box_screen), do: json(conn, today)
  end

  operation(:token,
    summary: "Renew the display token",
    responses: [
      ok: {"Display token", "application/json", S.token_response()},
      unauthorized: {"Invalid display token", "application/json", S.error()}
    ]
  )

  def token(conn, _params) do
    with {:ok, token} <- BoxScreenDisplay.renew(conn.assigns.box_screen), do: json(conn, token)
  end

  operation(:class_timer,
    summary: "A class's timer, for a class the screen shows",
    parameters: [
      %Parameter{name: :slot_id, in: :path, required: true, schema: S.uuid()}
    ],
    responses: [
      ok: {"Class timer", "application/json", ClassTimerController.payload_schema()},
      not_found: {"Not on this screen", "application/json", S.error()}
    ]
  )

  def class_timer(conn, %{slot_id: slot_id}) do
    with {:ok, payload} <- BoxScreenDisplay.class_timer(conn.assigns.box_screen, slot_id),
         do: json(conn, payload)
  end
end
