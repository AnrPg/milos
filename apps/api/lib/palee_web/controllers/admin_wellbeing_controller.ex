defmodule PaleeWeb.AdminWellbeingController do
  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.{
    AdminReportInjury,
    ChangeInjury,
    ListAdminInjuries,
    MarkInjuryHealed
  }

  alias PaleeWeb.Schemas.FeedbackWellbeing
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Admin Wellbeing"])
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
      visibility: %Schema{type: :string, enum: ["admin_only", "user_and_admin"], nullable: true}
    },
    required: [:body_area, :severity],
    additionalProperties: false
  }
  @heal_schema %Schema{
    type: :object,
    properties: %{healed_on: %Schema{type: :string, format: :date, nullable: true}},
    additionalProperties: false
  }
  @id_parameter %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
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
    summary: "List injury reports for admin review",
    parameters: [
      %Parameter{name: :status, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :severity, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :body_area, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{
        name: :limit,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 1, maximum: 250}
      },
      %Parameter{
        name: :offset,
        in: :query,
        required: false,
        schema: %Schema{type: :integer, minimum: 0}
      }
    ],
    responses: [ok: {"Injury reports", "application/json", FeedbackWellbeing.injury_collection()}]
  )

  def index(conn, params) do
    with {:ok, payload} <- ListAdminInjuries.call(conn.assigns.tenant_context, params) do
      json(conn, payload)
    end
  end

  operation(:create,
    summary: "Report an injury on behalf of a user",
    parameters: [@id_parameter],
    request_body: @injury_request_body,
    responses: [
      created: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}
    ]
  )

  def create(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           AdminReportInjury.call(
             conn.assigns.tenant_context,
             admin.id,
             param_id(params),
             body_params(conn, params)
           ) do
      conn
      |> put_status(:created)
      |> json(%{injury: injury})
    end
  end

  operation(:heal,
    summary: "Mark an injury report healed",
    parameters: [@id_parameter],
    request_body: @heal_request_body,
    responses: [ok: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}]
  )

  def heal(conn, params) do
    admin = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           MarkInjuryHealed.call(
             conn.assigns.tenant_context,
             admin.id,
             param_id(params),
             body_params(conn, params)
           ) do
      json(conn, %{injury: injury})
    end
  end

  operation(:update,
    summary: "Add an update to an injury (text and/or field changes) on its timeline",
    parameters: [@id_parameter],
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
           ChangeInjury.update(
             conn.assigns.tenant_context,
             actor.id,
             param_id(params),
             body_params(conn, params)
           ) do
      json(conn, %{injury: injury})
    end
  end

  operation(:reopen,
    summary: "Reopen a healed injury",
    parameters: [@id_parameter],
    responses: [ok: {"Injury report", "application/json", FeedbackWellbeing.injury_response()}]
  )

  def reopen(conn, params) do
    actor = Guardian.Plug.current_resource(conn)

    with {:ok, injury} <-
           ChangeInjury.reopen(conn.assigns.tenant_context, actor.id, param_id(params)) do
      json(conn, %{injury: injury})
    end
  end

  defp param_id(params), do: params["id"] || params[:id]

  defp body_params(conn, _params), do: Map.drop(conn.body_params, ["id", :id])
end
