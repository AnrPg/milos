defmodule MilosTrainingWeb.DevicesController do
  @moduledoc """
  Εγώ › Συνδεδεμένες συσκευές, Garmin's row and the journal's device card
  (ADR-161, P2-M13).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    ConnectedDevices,
    DeviceImports,
    GarminConnection
  }

  alias MilosTrainingWeb.Schemas.CheckIn
  alias MilosTrainingWeb.Schemas.Devices, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Connected devices"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  operation(:index,
    summary: "Wallet cards, calendar feed and health integrations, with Garmin's status",
    responses: [ok: {"Connected devices", "application/json", CheckIn.devices_response()}]
  )

  def index(conn, _params) do
    with {:ok, devices} <-
           ConnectedDevices.call(conn.assigns.user_context, GuardianPlug.current_resource(conn)),
         do: json(conn, devices)
  end

  operation(:connect,
    summary: "Start connecting Garmin: choose what syncs and how far back, get Garmin's sign-in",
    request_body: S.body(S.connect_request()),
    responses: [
      ok: {"Garmin sign-in", "application/json", S.connect_response()},
      service_unavailable:
        {"Garmin isn't available on this server", "application/json", S.error()},
      forbidden: {"Health-data consent needed", "application/json", S.error()},
      conflict: {"Already connected", "application/json", S.error()}
    ]
  )

  def connect(conn, _params) do
    with {:ok, result} <- GarminConnection.connect(conn.assigns.user_context, conn.body_params),
         do: json(conn, result)
  end

  operation(:update,
    summary: "Change what Garmin syncs",
    request_body: S.body(S.update_request()),
    responses: [
      ok: {"The Garmin row", "application/json", S.garmin_row_response()},
      unprocessable_entity: {"Not connected or invalid", "application/json", S.error()}
    ]
  )

  def update(conn, _params) do
    with {:ok, row} <- GarminConnection.update(conn.assigns.user_context, conn.body_params),
         do: json(conn, %{garmin: row})
  end

  operation(:sync,
    summary: "«Συγχρονισμός τώρα»: Garmin resends the last two days (at most every 5 minutes)",
    responses: [
      ok: {"The Garmin row", "application/json", S.garmin_row_response()},
      too_many_requests: {"Asked too recently", "application/json", S.error()}
    ]
  )

  def sync(conn, _params) do
    with {:ok, row} <- GarminConnection.sync_now(conn.assigns.user_context),
         do: json(conn, %{garmin: row})
  end

  operation(:disconnect,
    summary: "Disconnect Garmin, keeping or deleting what it brought in",
    parameters: [
      %Parameter{
        name: :delete_data,
        in: :query,
        required: false,
        schema: %Schema{type: :boolean, default: false}
      }
    ],
    responses: [
      ok: {"Disconnected", "application/json", S.disconnect_response()},
      not_found: {"Never connected", "application/json", S.error()}
    ]
  )

  def disconnect(conn, params) do
    delete? = Map.get(params, :delete_data, false) in [true, "true"]

    with {:ok, result} <- GarminConnection.disconnect(conn.assigns.user_context, delete?),
         do: json(conn, result)
  end

  operation(:pending,
    summary: "Garmin workouts that could be one of two classes or workouts",
    responses: [ok: {"Waiting for an answer", "application/json", S.pending_response()}]
  )

  def pending(conn, _params) do
    with {:ok, imports} <- DeviceImports.pending(conn.assigns.user_context),
         do: json(conn, %{imports: imports})
  end

  operation(:confirm,
    summary: "Answer «Ήταν αυτό το …;»: merge into one candidate or keep as its own entry",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: S.body(S.confirm_request()),
    responses: [
      ok: {"The workout", "application/json", S.activity_response()},
      not_found: {"No such import", "application/json", S.error()},
      unprocessable_entity: {"Invalid answer", "application/json", S.error()}
    ]
  )

  def confirm(conn, %{id: id}) do
    with {:ok, activity} <-
           DeviceImports.confirm(conn.assigns.user_context, id, conn.body_params),
         do: json(conn, %{activity: activity})
  end

  operation(:summary,
    summary: "The journal's device card: new imports since last seen, and what needs an answer",
    responses: [ok: {"Device card", "application/json", S.summary_response()}]
  )

  def summary(conn, _params) do
    with {:ok, summary} <- DeviceImports.summary(conn.assigns.user_context),
         do: json(conn, summary)
  end

  operation(:seen,
    summary: "The device card was seen: it hides until something new arrives",
    responses: [ok: {"Device card", "application/json", S.summary_response()}]
  )

  def seen(conn, _params) do
    with {:ok, summary} <- DeviceImports.mark_seen(conn.assigns.user_context),
         do: json(conn, summary)
  end
end
