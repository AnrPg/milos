defmodule MilosTrainingWeb.TrainingDepthController do
  @moduledoc """
  The Πρόοδος depth sections (ADR-165): muscle coverage, the qualities
  radar and training load, for the member across every provider and for a
  coach's view of one client (only what the client shares with the gym).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{GetClientTrainingDepth, GetMyTrainingDepth}
  alias MilosTrainingWeb.Schemas.TrainingDepth
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Progress"])
  security([%{"bearerAuth" => []}])

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  @ranges ["4w", "12w", "6m", "1y", "all"]

  @error {"Error", "application/json",
          %Schema{type: :object, properties: %{error: %Schema{type: :string}}}}

  operation(:show,
    summary: "Your muscle coverage, qualities radar and training load across every provider",
    parameters: [
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: @ranges, default: "all"}
      },
      %Parameter{
        name: :sources,
        in: :query,
        required: false,
        description: "Comma-separated provider ids, `freeform`, `device` (all when absent)",
        schema: %Schema{type: :string}
      }
    ],
    responses: [ok: {"Training depth", "application/json", TrainingDepth.my_depth_response()}]
  )

  def show(conn, params) do
    with {:ok, depth} <- GetMyTrainingDepth.call(conn.assigns.user_context, query(params)) do
      json(conn, depth)
    end
  end

  operation(:client,
    summary: "A client's muscle coverage, qualities radar and training load, from shared entries",
    parameters: [
      %Parameter{
        name: :user_id,
        in: :path,
        required: true,
        schema: %Schema{type: :string, format: :uuid}
      },
      %Parameter{
        name: :range,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: @ranges, default: "4w"}
      }
    ],
    responses: [
      ok: {"Client training depth", "application/json", TrainingDepth.client_depth_response()},
      forbidden: @error,
      not_found: @error
    ]
  )

  def client(conn, %{user_id: user_id} = params) do
    with {:ok, depth} <-
           GetClientTrainingDepth.call(conn.assigns.tenant_context, user_id, query(params)) do
      json(conn, depth)
    end
  end

  defp query(params) do
    params
    |> Map.take([:range, :sources])
    |> Map.new(fn {key, value} -> {to_string(key), value} end)
  end
end
