defmodule MilosTrainingWeb.AdminReviewController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{ListAdminReviews, UpdateReviewStatus}
  alias MilosTrainingWeb.Schemas.FeedbackWellbeing
  alias OpenApiSpex.{MediaType, Parameter, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Admin Reviews"])
  security([%{"bearerAuth" => []}])

  @moderation_update_schema %Schema{
    type: :object,
    properties: %{
      status: %Schema{type: :string, enum: ["open", "reviewed", "archived", "needs_follow_up"]},
      tags: %Schema{type: :array, items: %Schema{type: :string}, nullable: true}
    },
    required: [:status],
    additionalProperties: false
  }

  operation(:index,
    summary: "List user reviews for admin moderation and analytics",
    parameters: [
      %Parameter{name: :target_type, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :status, in: :query, required: false, schema: %Schema{type: :string}},
      %Parameter{name: :sentiment, in: :query, required: false, schema: %Schema{type: :string}},
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
    responses: [ok: {"Reviews", "application/json", FeedbackWellbeing.review_collection()}]
  )

  def index(conn, params) do
    with {:ok, payload} <- ListAdminReviews.call(params) do
      json(conn, payload)
    end
  end

  operation(:update_status,
    summary: "Update review moderation status",
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
      content: %{"application/json" => %MediaType{schema: @moderation_update_schema}}
    },
    responses: [ok: {"Review", "application/json", FeedbackWellbeing.review_response()}]
  )

  def update_status(conn, params) do
    with {:ok, review} <- UpdateReviewStatus.call(params["id"], body_params(conn, params)) do
      json(conn, %{review: review})
    end
  end

  defp body_params(conn, params), do: Map.drop(conn.body_params || params, ["id"])
end
