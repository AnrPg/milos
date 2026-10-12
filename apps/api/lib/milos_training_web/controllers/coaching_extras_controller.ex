defmodule MilosTrainingWeb.CoachingExtrasController do
  @moduledoc """
  Phase C coaching (ADR-098): form reviews and nutrition plans for clients,
  and the form-review and reply queues for staff (owners, admins, coaches).
  """

  use MilosTrainingWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Guardian.Plug, as: GuardianPlug

  alias MilosTraining.Application.{
    CompleteFormReview,
    GetMyNutritionPlan,
    ListCoachingReplyQueue,
    SaveNutritionPlan,
    SubmitFormReview,
    WithdrawFormReview
  }

  alias MilosTraining.{Coaching, Nutrition}
  alias MilosTrainingWeb.Schemas.Coaching, as: CoachingSchemas
  alias OpenApiSpex.{Parameter, Schema}

  action_fallback MilosTrainingWeb.FallbackController

  tags(["Coaching"])
  security([%{"bearerAuth" => []}])

  plug OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_string %Schema{type: :string, nullable: true}
  @date_time %Schema{type: :string, format: :"date-time", nullable: true}
  @error %Schema{type: :object, additionalProperties: true}
  @id %Parameter{name: :id, in: :path, required: true, schema: @uuid}
  @user_id %Parameter{name: :user_id, in: :path, required: true, schema: @uuid}

  # Client

  operation(:my_form_reviews,
    summary: "My form reviews",
    responses: [ok: {"Form reviews", "application/json", CoachingSchemas.reviews_response()}]
  )

  def my_form_reviews(conn, _params) do
    actor = GuardianPlug.current_resource(conn)
    reviews = Coaching.list_form_reviews(conn.assigns.tenant_context, %{user_id: actor.id})
    json(conn, %{form_reviews: reviews})
  end

  operation(:submit_form_review,
    summary: "Ask a coach for feedback on a video of my technique",
    request_body:
      CoachingSchemas.body(%Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          video_url: %Schema{type: :string, maxLength: 2000},
          note: %Schema{type: :string, maxLength: 2000, nullable: true},
          exercise_name: %Schema{type: :string, maxLength: 120, nullable: true},
          execution_id: %Schema{type: :string, format: :uuid, nullable: true}
        },
        required: [:video_url]
      }),
    responses: [
      created: {"Form review", "application/json", CoachingSchemas.review_response()},
      forbidden: {"Not included or used up", "application/json", @error},
      conflict: {"Used up", "application/json", @error}
    ]
  )

  def submit_form_review(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, review} <-
           SubmitFormReview.call(conn.assigns.tenant_context, actor, conn.body_params) do
      conn |> put_status(:created) |> json(%{form_review: review})
    end
  end

  operation(:withdraw_form_review,
    summary: "Withdraw an open form review; the review is given back",
    parameters: [@id],
    responses: [
      ok: {"Form review", "application/json", CoachingSchemas.review_response()},
      conflict: {"Already reviewed or withdrawn", "application/json", @error}
    ]
  )

  def withdraw_form_review(conn, %{id: id}) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, review} <- WithdrawFormReview.call(conn.assigns.tenant_context, actor, id) do
      json(conn, %{form_review: review})
    end
  end

  operation(:my_nutrition_plan,
    summary: "My nutrition plan",
    responses: [
      ok: {"Nutrition plan", "application/json", CoachingSchemas.plan_response()},
      forbidden: {"Not included in the package", "application/json", @error}
    ]
  )

  def my_nutrition_plan(conn, _params) do
    actor = GuardianPlug.current_resource(conn)

    with {:ok, plan} <- GetMyNutritionPlan.call(conn.assigns.tenant_context, actor) do
      json(conn, %{nutrition_plan: plan})
    end
  end

  # Staff

  operation(:form_review_queue,
    summary: "Form reviews, open ones by default",
    parameters: [
      %Parameter{
        name: :status,
        in: :query,
        required: false,
        schema: %Schema{type: :string, enum: ["submitted", "reviewed", "withdrawn"]}
      }
    ],
    responses: [ok: {"Form reviews", "application/json", CoachingSchemas.reviews_response()}]
  )

  def form_review_queue(conn, params) do
    status = Map.get(params, :status, "submitted")
    reviews = Coaching.list_form_reviews(conn.assigns.tenant_context, %{status: status})
    json(conn, %{form_reviews: reviews})
  end

  operation(:complete_form_review,
    summary: "Answer a form review",
    parameters: [@id],
    request_body:
      CoachingSchemas.body(%Schema{
        type: :object,
        properties: %{feedback: %Schema{type: :string, minLength: 2, maxLength: 5000}},
        required: [:feedback]
      }),
    responses: [
      ok: {"Form review", "application/json", CoachingSchemas.review_response()},
      conflict: {"Already closed", "application/json", @error}
    ]
  )

  def complete_form_review(conn, %{id: id}) do
    staff = GuardianPlug.current_resource(conn)
    feedback = Map.get(conn.body_params, :feedback)

    with {:ok, review} <-
           CompleteFormReview.call(conn.assigns.tenant_context, staff, id, feedback) do
      json(conn, %{form_review: review})
    end
  end

  operation(:reply_queue,
    summary: "Client messages waiting for a staff reply, overdue first",
    responses: [
      ok:
        {"Reply queue", "application/json",
         %Schema{
           type: :object,
           properties: %{
             replies: %Schema{
               type: :array,
               items: %Schema{
                 type: :object,
                 properties: %{
                   thread_id: @uuid,
                   message_id: @uuid,
                   client_id: @uuid,
                   client_nickname: @nullable_string,
                   sent_at: %Schema{type: :string, format: :"date-time"},
                   response_sla_hours: %Schema{type: :integer, nullable: true},
                   due_at: @date_time,
                   overdue: %Schema{type: :boolean}
                 },
                 required: [:thread_id, :message_id, :client_id, :sent_at, :overdue]
               }
             }
           },
           required: [:replies]
         }}
    ]
  )

  def reply_queue(conn, _params) do
    json(conn, %{replies: ListCoachingReplyQueue.call(conn.assigns.tenant_context)})
  end

  operation(:nutrition_plan,
    summary: "A client's nutrition plan",
    parameters: [@user_id],
    responses: [ok: {"Nutrition plan", "application/json", CoachingSchemas.plan_response()}]
  )

  def nutrition_plan(conn, %{user_id: user_id}) do
    json(conn, %{nutrition_plan: Nutrition.get_plan(conn.assigns.tenant_context, user_id)})
  end

  operation(:save_nutrition_plan,
    summary: "Write a client's nutrition plan; the client is notified",
    parameters: [@user_id],
    request_body:
      CoachingSchemas.body(%Schema{
        type: :object,
        additionalProperties: false,
        properties: %{
          title: %Schema{type: :string, minLength: 2, maxLength: 120},
          body: %Schema{type: :string, minLength: 2, maxLength: 20_000},
          daily_calories: %Schema{type: :integer, minimum: 1, maximum: 10_000, nullable: true},
          protein_grams: %Schema{type: :integer, minimum: 0, maximum: 1000, nullable: true},
          carbs_grams: %Schema{type: :integer, minimum: 0, maximum: 2000, nullable: true},
          fat_grams: %Schema{type: :integer, minimum: 0, maximum: 1000, nullable: true}
        },
        required: [:title, :body]
      }),
    responses: [
      ok: {"Nutrition plan", "application/json", CoachingSchemas.plan_response()},
      not_found: {"Not a client of this gym", "application/json", @error}
    ]
  )

  def save_nutrition_plan(conn, %{user_id: user_id}) do
    staff = GuardianPlug.current_resource(conn)

    with {:ok, plan} <-
           SaveNutritionPlan.call(conn.assigns.tenant_context, staff, user_id, conn.body_params) do
      json(conn, %{nutrition_plan: plan})
    end
  end
end
