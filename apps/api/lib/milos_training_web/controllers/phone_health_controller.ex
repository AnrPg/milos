defmodule MilosTrainingWeb.PhoneHealthController do
  @moduledoc """
  Apple Health and Health Connect from the store apps, and the device-data
  export (ADR-172, P3-M10).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{DeviceData, PhoneHealthConnection}
  alias MilosTrainingWeb.Schemas.Devices
  alias MilosTrainingWeb.Schemas.PhoneHealth, as: S
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Connected devices"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @provider %Parameter{name: :provider, in: :path, required: true, schema: S.provider()}

  operation(:connect,
    summary: "Connect Apple Health or Health Connect after the phone granted read access",
    parameters: [@provider],
    request_body: Devices.body(S.connect_request()),
    responses: [
      ok: {"The phone's row", "application/json", S.row_response()},
      forbidden: {"Health-data consent needed", "application/json", Devices.error()},
      unprocessable_entity: {"Invalid choices", "application/json", Devices.error()}
    ]
  )

  def connect(conn, %{provider: provider}) do
    with {:ok, row} <-
           PhoneHealthConnection.connect(conn.assigns.user_context, provider, conn.body_params),
         do: json(conn, %{row: row})
  end

  operation(:update,
    summary: "Change what the phone brings in",
    parameters: [@provider],
    request_body: Devices.body(S.update_request()),
    responses: [
      ok: {"The phone's row", "application/json", S.row_response()},
      forbidden: {"Health-data consent needed", "application/json", Devices.error()},
      unprocessable_entity: {"Not connected or invalid", "application/json", Devices.error()}
    ]
  )

  def update(conn, %{provider: provider}) do
    with {:ok, row} <-
           PhoneHealthConnection.update(conn.assigns.user_context, provider, conn.body_params),
         do: json(conn, %{row: row})
  end

  operation(:ingest,
    summary: "A batch the app read from the phone: workouts, nights, weigh-ins, daily numbers",
    parameters: [@provider],
    request_body: Devices.body(S.ingest_request()),
    responses: [
      ok: {"What happened to each record, and the row", "application/json", S.ingest_response()},
      unprocessable_entity:
        {"Not connected, or too many records", "application/json", Devices.error()}
    ]
  )

  def ingest(conn, %{provider: provider}) do
    with {:ok, result} <-
           PhoneHealthConnection.ingest(conn.assigns.user_context, provider, conn.body_params),
         do: json(conn, result)
  end

  operation(:disconnect,
    summary: "Disconnect the phone's health data, keeping or deleting what it brought in",
    parameters: [
      @provider,
      %Parameter{
        name: :delete_data,
        in: :query,
        required: false,
        schema: %Schema{type: :boolean, default: false}
      }
    ],
    responses: [
      ok: {"Disconnected", "application/json", Devices.disconnect_response()},
      not_found: {"Never connected", "application/json", Devices.error()}
    ]
  )

  def disconnect(conn, %{provider: provider} = params) do
    delete? = Map.get(params, :delete_data, false) in [true, "true"]

    with {:ok, result} <-
           PhoneHealthConnection.disconnect(conn.assigns.user_context, provider, delete?),
         do: json(conn, result)
  end

  operation(:export,
    summary:
      "Everything connected devices brought in, as JSON (workouts, daily stats, import log)",
    responses: [ok: {"Device data", "application/json", S.export_response()}]
  )

  def export(conn, _params) do
    json(conn, DeviceData.export(conn.assigns.user_context))
  end
end
