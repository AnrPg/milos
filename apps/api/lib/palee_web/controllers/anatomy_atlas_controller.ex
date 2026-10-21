defmodule PaleeWeb.AnatomyAtlasController do
  @moduledoc """
  The anatomy atlas (ADR-164): the member's own muscle coverage across every
  provider, and the exercises of the current gym that train one node.
  """

  use PaleeWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug
  alias Palee.Application.{GetMyAtlas, ListAtlasNodeExercises}
  alias PaleeWeb.Schemas.AnatomyAtlas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(PaleeWeb.FallbackController)

  tags(["Anatomy"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @not_found {"Not found", "application/json",
              %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}

  operation(:show,
    summary: "Your muscle coverage across every provider, for the anatomy atlas",
    parameters: [
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["1w", "4w", "12w"], default: "4w"}
      }
    ],
    responses: [ok: {"Atlas coverage", "application/json", AnatomyAtlas.atlas_response()}]
  )

  def show(conn, params) do
    query = %{"range" => Map.get(params, :range)}

    with {:ok, atlas} <- GetMyAtlas.call(conn.assigns.user_context, query) do
      json(conn, atlas)
    end
  end

  operation(:exercises,
    summary: "Exercises that train an atlas node, with the gym's videos",
    parameters: [
      %Parameter{
        name: :node_id,
        in: :path,
        required: true,
        description: "Taxonomy node id (region, group or head)",
        schema: %Schema{type: :string}
      }
    ],
    responses: [
      ok: {"Node exercises", "application/json", AnatomyAtlas.node_exercises_response()},
      not_found: @not_found
    ]
  )

  def exercises(conn, %{node_id: node_id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, result} <- ListAtlasNodeExercises.call(conn.assigns.tenant_context, actor, node_id) do
      json(conn, result)
    end
  end
end
