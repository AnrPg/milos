defmodule PaleeWeb.AdminCoachingController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.GetCoachingAthleteDrillDown
  alias OpenApiSpex.{Parameter, Schema}
  alias PaleeWeb.Schemas.AdminDrillDown

  action_fallback PaleeWeb.FallbackController

  tags(["Admin Coaching"])
  security([%{"bearerAuth" => []}])

  @drill_down_schema AdminDrillDown.coaching_drill_down_schema()

  operation(:drill_down,
    summary: "Fetch an athlete coaching drill-down",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        description: "Athlete ID",
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [
      ok:
        {"Athlete coaching drill-down", "application/json",
         %Schema{
           type: :object,
           properties: %{
             drill_down: @drill_down_schema
           },
           required: [:drill_down]
         }},
      not_found:
        {"Not found", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }},
      forbidden:
        {"Forbidden", "application/json",
         %Schema{
           type: :object,
           properties: %{error: %Schema{type: :string}},
           required: [:error]
         }}
    ]
  )

  def drill_down(conn, params) do
    athlete_id = params["id"] || params[:id]

    with {:ok, profile} <-
           GetCoachingAthleteDrillDown.call(conn.assigns.tenant_context, athlete_id, params) do
      json(conn, profile)
    end
  end
end
