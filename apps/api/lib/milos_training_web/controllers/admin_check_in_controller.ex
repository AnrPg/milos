defmodule MilosTrainingWeb.AdminCheckInController do
  @moduledoc """
  The check-in desk and «Οθόνη πόρτας» (ADR-155): the door display with its
  rotating code, scanning a member's personal QR or Wallet card, checking a
  member in (with the owner's override rule), today's visitors, and the
  owner's «Ρυθμίσεις › Check-in».
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{DeskCheckIn, DoorDisplay, UpdateCheckInRules}
  alias MilosTraining.Facility
  alias MilosTrainingWeb.Schemas.CheckIn, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Admin Check-in"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @location %Parameter{
    name: :location_id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:door,
    summary: "The door display of a location: its code, the next codes, the next class",
    parameters: [@location],
    responses: [
      ok: {"Door display", "application/json", S.door_response()},
      not_found: {"No such location", "application/json", S.error()}
    ]
  )

  def door(conn, %{location_id: location_id}) do
    with {:ok, display} <- DoorDisplay.show(conn.assigns.tenant_context, location_id),
         do: json(conn, display)
  end

  operation(:rotate_door,
    summary: "«Νέος κωδικός πόρτας»: every code shown so far stops working",
    parameters: [@location],
    responses: [
      ok: {"Door display", "application/json", S.door_response()},
      not_found: {"No such location", "application/json", S.error()}
    ]
  )

  def rotate_door(conn, %{location_id: location_id}) do
    with {:ok, display} <- DoorDisplay.rotate(conn.assigns.tenant_context, location_id),
         do: json(conn, display)
  end

  operation(:poster,
    summary: "The printed poster of a location: its static QR and whether it is on",
    parameters: [@location],
    responses: [
      ok: {"Poster", "application/json", S.poster_response()},
      not_found: {"No such location", "application/json", S.error()}
    ]
  )

  def poster(conn, %{location_id: location_id}) do
    with {:ok, poster} <- DoorDisplay.poster(conn.assigns.tenant_context, location_id),
         do: json(conn, poster)
  end

  operation(:update_poster,
    summary: "Turn the printed poster of a location on or off",
    parameters: [@location],
    request_body: S.body(S.poster_request()),
    responses: [
      ok: {"Poster", "application/json", S.poster_response()},
      not_found: {"No such location", "application/json", S.error()}
    ]
  )

  def update_poster(conn, %{location_id: location_id}) do
    with {:ok, poster} <-
           DoorDisplay.set_poster(
             conn.assigns.tenant_context,
             location_id,
             conn.body_params.enabled
           ),
         do: json(conn, poster)
  end

  operation(:rotate_poster,
    summary: "«Νέος κωδικός αφίσας»: every printed copy stops working",
    parameters: [@location],
    responses: [
      ok: {"Poster", "application/json", S.poster_response()},
      not_found: {"No such location", "application/json", S.error()}
    ]
  )

  def rotate_poster(conn, %{location_id: location_id}) do
    with {:ok, poster} <- DoorDisplay.rotate_poster(conn.assigns.tenant_context, location_id),
         do: json(conn, poster)
  end

  operation(:revoke_member_code,
    summary: "Revoke a member's static personal code; their Wallet cards stop scanning",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Revoked", "application/json", S.member_code_revoked_response()}
    ]
  )

  def revoke_member_code(conn, %{user_id: user_id}) do
    with {:ok, result} <- DeskCheckIn.revoke_member_code(conn.assigns.tenant_context, user_id),
         do: json(conn, result)
  end

  operation(:scan_member,
    summary: "Scan a member's personal QR or Wallet card at the desk",
    request_body: S.body(S.scan_member_request()),
    responses: [
      ok: {"Who it is and what can happen", "application/json", S.desk_response()},
      unprocessable_entity: {"Unknown, expired or revoked code", "application/json", S.error()}
    ]
  )

  def scan_member(conn, _params) do
    with {:ok, result} <-
           DeskCheckIn.scan_member(conn.assigns.tenant_context, staff(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:check_in_member,
    summary: "Check a member in from the desk (booking in the window, else open gym)",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: S.body(S.check_in_member_request()),
    responses: [
      ok: {"Checked in", "application/json", S.desk_response()},
      conflict:
        {"Problems with the package, or a booking to pick", "application/json", S.error()},
      forbidden: {"The owner doesn't allow desk overrides", "application/json", S.error()}
    ]
  )

  def check_in_member(conn, %{user_id: user_id}) do
    with {:ok, result} <-
           DeskCheckIn.check_in_member(
             conn.assigns.tenant_context,
             staff(conn),
             user_id,
             conn.body_params || %{}
           ),
         do: json(conn, result)
  end

  operation(:visitors,
    summary: "People who scanned the door and are not members («Επισκέπτης»), newest first",
    parameters: [
      %Parameter{
        name: :date,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :date}
      },
      %Parameter{
        name: :location_id,
        in: :query,
        required: false,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Visitors", "application/json", S.visitors_response()}]
  )

  def visitors(conn, params) do
    json(conn, %{visitors: DeskCheckIn.visitors(conn.assigns.tenant_context, params)})
  end

  operation(:settings,
    summary: "The box's check-in rules",
    responses: [ok: {"Rules", "application/json", S.rules_response()}]
  )

  def settings(conn, _params),
    do: json(conn, %{settings: Facility.check_in_rules(conn.assigns.tenant_context)})

  operation(:update_settings,
    summary: "Change the box's check-in rules",
    request_body: S.body(S.rules()),
    responses: [
      ok: {"Rules", "application/json", S.rules_response()},
      unprocessable_entity: {"Invalid rules", "application/json", S.error()}
    ]
  )

  def update_settings(conn, _params) do
    with {:ok, settings} <-
           UpdateCheckInRules.call(conn.assigns.tenant_context, conn.body_params),
         do: json(conn, %{settings: settings})
  end

  defp staff(conn), do: GuardianPlug.current_resource(conn)
end
