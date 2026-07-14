defmodule MilosTrainingWeb.WellbeingController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{ListMyInjuries, MarkMyInjuryHealed, ReportInjury}
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Wellbeing"])
  security([%{"bearerAuth" => []}])

  @open_object %Schema{type: :object, additionalProperties: true}
  @injury_report_schema %Schema{
    type: :object,
    properties: %{
      body_area: %Schema{type: :string},
      severity: %Schema{type: :string, enum: ["mild", "moderate", "severe"]},
      started_on: %Schema{type: :string, format: :date, nullable: true},
      description: %Schema{type: :string, nullable: true},
      training_limitations: %Schema{type: :string, nullable: true},
      tags: %Schema{type: :array, items: %Schema{type: :string}, nullable: true},
      params: %Schema{type: :object, additionalProperties: true, nullable: true}
    },
    required: [:body_area, :severity],
    additionalProperties: false
  }
  @heal_schema %Schema{
    type: :object,
    properties: %{healed_on: %Schema{type: :string, format: :date, nullable: true}},
    additionalProperties: false
  }
  @injury_request_body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: @injury_report_schema}}
  }
  @heal_request_body %RequestBody{
    required: true,
    content: %{"application/json" => %MediaType{schema: @heal_schema}}
  }

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    [json_render_error_v2: true] when action in [:create, :heal]
  )

  operation(:index,
    summary: "List the current user's injury history",
    responses: [ok: {"Injury reports", "application/json", @open_object}]
  )

  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, payload} <- ListMyInjuries.call(current_user.id) do
      json(conn, payload)
    end
  end

  operation(:create,
    summary: "Report an injury for the current user",
    request_body: @injury_request_body,
    responses: [created: {"Injury report", "application/json", @open_object}]
  )

  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <- ReportInjury.call(current_user.id, body_params(conn, params)) do
      conn
      |> put_status(:created)
      |> json(%{injury: injury})
    end
  end

  operation(:heal,
    summary: "Mark one of the current user's injuries healed",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: @heal_request_body,
    responses: [ok: {"Injury report", "application/json", @open_object}]
  )

  def heal(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           MarkMyInjuryHealed.call(current_user.id, param_id(params), body_params(conn, params)) do
      json(conn, %{injury: injury})
    end
  end

  defp param_id(params), do: params["id"] || params[:id]

  defp body_params(conn, params), do: Map.drop(conn.body_params || params, ["id", :id])
end
