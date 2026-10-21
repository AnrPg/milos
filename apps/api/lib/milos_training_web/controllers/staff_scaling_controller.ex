defmodule MilosTrainingWeb.StaffScalingController do
  @moduledoc """
  The coach's approval queue for AI scaling suggestions (ADR-174): only
  athletes the coach may manage and whose health data they may see; nothing
  reaches the athlete until it is approved here.
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.ScalingSuggestions
  alias MilosTrainingWeb.Schemas.Scaling, as: ScalingSchemas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Coaching"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @error %Schema{type: :object, additionalProperties: true}
  @id %Parameter{
    name: :id,
    in: :path,
    required: true,
    schema: %Schema{type: :string, format: :uuid}
  }

  operation(:index,
    summary: "AI scaling suggestions waiting for the coach (pending by default)",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ~w(pending approved dismissed)}
      }
    ],
    responses: [ok: {"Suggestions", "application/json", ScalingSchemas.queue_response()}]
  )

  def index(conn, params) do
    suggestions =
      ScalingSuggestions.queue(conn.assigns.tenant_context, %{
        status: Map.get(params, :status, "pending")
      })

    json(conn, %{suggestions: suggestions})
  end

  operation(:approve,
    summary: "Approve a suggestion, optionally edited; it becomes the athlete's modifications",
    parameters: [@id],
    request_body: ScalingSchemas.body(ScalingSchemas.approve_request()),
    responses: [
      ok: {"Suggestion", "application/json", ScalingSchemas.suggestion_response()},
      not_found: {"Not found", "application/json", @error},
      conflict: {"Already reviewed", "application/json", @error},
      unprocessable_entity: {"Invalid review", "application/json", @error}
    ]
  )

  def approve(conn, %{id: id}) do
    params = Map.take(conn.body_params, [:items, :scale_level_slug, :coach_note])

    conn.assigns.tenant_context
    |> ScalingSuggestions.approve(id, params)
    |> respond(conn)
  end

  operation(:dismiss,
    summary: "Dismiss a suggestion; nothing reaches the athlete",
    parameters: [@id],
    responses: [
      ok: {"Suggestion", "application/json", ScalingSchemas.suggestion_response()},
      not_found: {"Not found", "application/json", @error},
      conflict: {"Already reviewed", "application/json", @error}
    ]
  )

  def dismiss(conn, %{id: id}) do
    conn.assigns.tenant_context
    |> ScalingSuggestions.dismiss(id)
    |> respond(conn)
  end

  defp respond({:ok, suggestion}, conn), do: json(conn, %{suggestion: suggestion})

  defp respond({:error, :already_reviewed}, conn),
    do: error(conn, :conflict, "already_reviewed")

  defp respond({:error, reason}, conn)
       when reason in [
              :nothing_to_approve,
              :invalid_suggested,
              :invalid_coach_note,
              :invalid_modification,
              :bad_request
            ],
       do: error(conn, :unprocessable_entity, Atom.to_string(reason))

  defp respond({:error, _reason} = error, _conn), do: error

  defp error(conn, status, code) do
    conn |> put_status(status) |> json(%{code: code, error: code})
  end
end
