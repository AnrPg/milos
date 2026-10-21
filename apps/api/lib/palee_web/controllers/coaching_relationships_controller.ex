defmodule PaleeWeb.CoachingRelationshipsController do
  @moduledoc "Who coaches whom (ADR-100)."

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Palee.Application.ManageCoachingRelationships
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback PaleeWeb.FallbackController

  tags(["Coaching relationships"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}

  @relationship %Schema{
    title: "CoachingRelationship",
    type: :object,
    properties: %{
      id: @uuid,
      coach_user_id: @uuid,
      coach_nickname: %Schema{type: :string, nullable: true},
      client_user_id: @uuid,
      client_nickname: %Schema{type: :string, nullable: true},
      origin: %Schema{type: :string, enum: ["assigned", "self_assigned", "invited"]},
      started_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :coach_user_id, :client_user_id, :origin]
  }

  @one %Schema{
    type: :object,
    properties: %{relationship: @relationship},
    required: [:relationship]
  }

  operation(:index,
    summary: "Coaching relationships: a coach's own, or all for owners, admins and head coaches",
    parameters: [
      %Parameter{name: :coach_user_id, in: :query, required: false, schema: @uuid},
      %Parameter{name: :client_user_id, in: :query, required: false, schema: @uuid}
    ],
    responses: [
      ok:
        {"Relationships", "application/json",
         %Schema{
           type: :object,
           properties: %{relationships: %Schema{type: :array, items: @relationship}},
           required: [:relationships]
         }}
    ]
  )

  def index(conn, params) do
    filters =
      params
      |> Map.take([:coach_user_id, :client_user_id])
      |> Map.reject(fn {_key, value} -> is_nil(value) end)

    json(conn, %{
      relationships: ManageCoachingRelationships.list(conn.assigns.tenant_context, filters)
    })
  end

  operation(:create,
    summary: "Assign a coach to a client (owners, admins) or take an athlete yourself (coaches)",
    request_body: %RequestBody{
      required: true,
      content: %{
        "application/json" => %MediaType{
          schema: %Schema{
            type: :object,
            properties: %{
              client_user_id: @uuid,
              coach_user_id: %Schema{type: :string, format: :uuid, nullable: true}
            },
            required: [:client_user_id]
          }
        }
      }
    },
    responses: [created: {"Relationship", "application/json", @one}]
  )

  def create(conn, _params) do
    context = conn.assigns.tenant_context
    client_id = Map.get(conn.body_params, :client_user_id)
    coach_id = Map.get(conn.body_params, :coach_user_id)

    result =
      if is_nil(coach_id) or coach_id == context.user_id,
        do: ManageCoachingRelationships.self_assign(context, client_id),
        else: ManageCoachingRelationships.assign(context, coach_id, client_id)

    with {:ok, relationship} <- result do
      conn |> put_status(:created) |> json(%{relationship: relationship})
    end
  end

  operation(:finish,
    summary: "End a coaching relationship",
    parameters: [%Parameter{name: :id, in: :path, required: true, schema: @uuid}],
    responses: [ok: {"Relationship", "application/json", @one}]
  )

  def finish(conn, %{id: id}) do
    with {:ok, relationship} <-
           ManageCoachingRelationships.finish(conn.assigns.tenant_context, id) do
      json(conn, %{relationship: relationship})
    end
  end
end
