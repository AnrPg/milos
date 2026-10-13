defmodule MilosTrainingWeb.AdminInjuryWarningController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{
    AcknowledgeAthleteInjuryWarnings,
    EvaluateAthleteInjuryWarnings,
    ListClassSlotInjuryWarnings
  }

  alias MilosTrainingWeb.Schemas.InjuryWarnings
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Admin Wellbeing"])
  security([%{"bearerAuth" => []}])

  @staff_request_body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: InjuryWarnings.staff_request()}}
  }

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  operation(:evaluate,
    summary: "Injury safety warnings for athletes against a workout",
    description:
      "Informational only (ADR-124). Only injuries with this organization's provenance are considered; members' personal self-reports are never visible to staff.",
    request_body: @staff_request_body,
    responses: [
      ok: {"Injury warnings", "application/json", InjuryWarnings.staff_result()}
    ]
  )

  def evaluate(conn, _params) do
    with {:ok, result} <-
           EvaluateAthleteInjuryWarnings.call(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:acknowledge,
    summary: "Acknowledge injury safety warnings shown for athletes",
    description:
      "Records an analytics acknowledgement for each warned athlete. Warnings are re-evaluated server-side and never block.",
    request_body: @staff_request_body,
    responses: [
      ok: {"Acknowledged", "application/json", InjuryWarnings.staff_ack()}
    ]
  )

  def acknowledge(conn, _params) do
    with {:ok, result} <-
           AcknowledgeAthleteInjuryWarnings.call(conn.assigns.tenant_context, conn.body_params) do
      json(conn, result)
    end
  end

  operation(:slot,
    summary: "Injury safety warnings for the members booked into a class slot",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok: {"Injury warnings", "application/json", InjuryWarnings.slot_result()}
    ]
  )

  def slot(conn, params) do
    with {:ok, result} <-
           ListClassSlotInjuryWarnings.call(
             conn.assigns.tenant_context,
             params[:id] || params["id"]
           ) do
      json(conn, result)
    end
  end
end
