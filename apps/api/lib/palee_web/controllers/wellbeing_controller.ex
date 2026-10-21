defmodule PaleeWeb.WellbeingController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{ChangeInjury, ListMyInjuries, MarkMyInjuryHealed, ReportInjury}
  alias PaleeWeb.Schemas.FeedbackWellbeing
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Wellbeing"])
  security([%{"bearerAuth" => []}])

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
    [json_render_error_v2: true] when action in [:create, :heal, :update]
  )

  operation(:index,
    summary: "List the current user's injury history",
    responses: [ok: {"Injury reports", "application/json", FeedbackWellbeing.injury_collection()}]
  )

  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, payload} <- ListMyInjuries.call(conn.assigns.user_context, current_user.id) do
      json(conn, payload)
    end
  end

  operation(:create,
    summary: "Report an injury for the current user",
    request_body: @injury_request_body,
    responses: [
      created: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}
    ]
  )

  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           ReportInjury.call(
             conn.assigns.user_context,
             current_user.id,
             body_params(conn, params)
           ) do
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
    responses: [ok: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}]
  )

  def heal(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           MarkMyInjuryHealed.call(
             conn.assigns.user_context,
             current_user.id,
             param_id(params),
             body_params(conn, params)
           ) do
      json(conn, %{injury: injury})
    end
  end

  operation(:update,
    summary: "Add an update to an injury (text and/or field changes) on its timeline",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{schema: FeedbackWellbeing.injury_update_request()}
      }
    },
    responses: [ok: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}]
  )

  def update(conn, params) do
    actor = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           ChangeInjury.update_mine(
             conn.assigns.user_context,
             actor.id,
             param_id(params),
             body_params(conn, params)
           ) do
      json(conn, %{injury: injury})
    end
  end

  operation(:reopen,
    summary: "Reopen a healed injury",
    parameters: [
      %Parameter{
        name: :id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      }
    ],
    responses: [ok: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}]
  )

  def reopen(conn, params) do
    actor = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           ChangeInjury.reopen_mine(conn.assigns.user_context, actor.id, param_id(params)) do
      json(conn, %{injury: injury})
    end
  end

  defp param_id(params), do: params["id"] || params[:id]

  defp body_params(conn, _params), do: Map.drop(conn.body_params, ["id", :id])
end
