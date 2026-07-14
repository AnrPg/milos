defmodule MilosTrainingWeb.ReviewController do
  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias MilosTraining.Application.{ListMyReviews, SubmitReview}
  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  action_fallback(MilosTrainingWeb.FallbackController)

  tags(["Reviews"])
  security([%{"bearerAuth" => []}])

  @open_object %Schema{type: :object, additionalProperties: true}
  @review_answer_schema %Schema{
    type: :object,
    properties: %{
      question_key: %Schema{type: :string},
      question_text: %Schema{type: :string},
      answer_text: %Schema{type: :string},
      rating_value: %Schema{type: :integer, minimum: 1, maximum: 5, nullable: true}
    },
    required: [:question_key, :question_text, :answer_text],
    additionalProperties: false
  }
  @review_request_schema %Schema{
    type: :object,
    properties: %{
      target_type: %Schema{
        type: :string,
        enum: [
          "workout",
          "execution",
          "exercise",
          "class_slot",
          "gym_parameter",
          "coaching_parameter",
          "membership_package",
          "app",
          "general"
        ]
      },
      target_id: %Schema{type: :string, format: :uuid, nullable: true},
      rating: %Schema{type: :integer, minimum: 1, maximum: 5, nullable: true},
      sentiment: %Schema{type: :string, enum: ["positive", "neutral", "negative", "mixed"]},
      visibility: %Schema{type: :string, enum: ["admin_only", "user_visible"], nullable: true},
      body: %Schema{type: :string, nullable: true},
      answers: %Schema{type: :array, items: @review_answer_schema, minItems: 1}
    },
    required: [:target_type, :sentiment, :answers],
    additionalProperties: false
  }

  plug(
    OpenApiSpex.Plug.CastAndValidate,
    [json_render_error_v2: true] when action in [:create]
  )

  operation(:index,
    summary: "List reviews submitted by the current user",
    responses: [ok: {"Reviews", "application/json", @open_object}]
  )

  def index(conn, _params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, payload} <- ListMyReviews.call(current_user.id) do
      json(conn, payload)
    end
  end

  operation(:create,
    summary: "Submit a review for a workout, exercise, gym parameter, or coaching target",
    request_body: %RequestBody{
      required: true,
      content: %{"application/json" => %MediaType{schema: @review_request_schema}}
    },
    responses: [created: {"Review", "application/json", @open_object}]
  )

  def create(conn, params) do
    current_user = Guardian.Plug.current_resource(conn)

    with {:ok, review} <- SubmitReview.call(current_user.id, conn.body_params || params) do
      conn
      |> put_status(:created)
      |> json(%{review: review})
    end
  end
end
