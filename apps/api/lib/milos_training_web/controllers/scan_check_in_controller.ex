defmodule MilosTrainingWeb.ScanCheckInController do
  @moduledoc """
  The door scan (ADR-155): a signed-in person scans the door QR with the
  phone camera, the app opens `/c/<location>/<code>` and posts it here.
  Not tied to one box: the door says which box it is. The store apps also
  read the arrival reminder's regions here (ADR-173).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias MilosTraining.Application.{CheckInGeofences, ScanCheckIn}
  alias MilosTrainingWeb.Schemas.CheckIn, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Check-in"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:scan,
    summary: "Scan the door: check in to a booking or open gym, or see what the box offers",
    request_body: S.body(S.scan_request()),
    responses: [
      ok: {"What the scan did", "application/json", S.scan_response()},
      unprocessable_entity:
        {"The door code is wrong or expired, or the booking isn't in its window",
         "application/json", S.error()}
    ]
  )

  def scan(conn, _params) do
    with {:ok, result} <- ScanCheckIn.scan(GuardianPlug.current_resource(conn), conn.body_params),
         do: json(conn, result)
  end

  operation(:geofences,
    summary:
      "Where the store app reminds the member to check in: locations with a booking soon (ADR-173)",
    responses: [ok: {"Regions", "application/json", S.geofences_response()}]
  )

  def geofences(conn, _params) do
    with {:ok, result} <- CheckInGeofences.call(conn.assigns.user_context),
         do: json(conn, result)
  end

  operation(:undo,
    summary: "Undo a scan's check-in within its minute",
    parameters: [
      %Parameter{name: :undo_token, in: :path, required: true, schema: %Schema{type: :string}}
    ],
    responses: [
      ok: {"Undone", "application/json", S.undo_response()},
      conflict: {"The minute has passed", "application/json", S.error()},
      not_found: {"Nothing to undo", "application/json", S.error()}
    ]
  )

  def undo(conn, %{undo_token: token}) do
    with {:ok, result} <- ScanCheckIn.undo(GuardianPlug.current_resource(conn), token),
         do: json(conn, result)
  end
end
