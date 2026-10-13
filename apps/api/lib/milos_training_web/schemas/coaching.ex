defmodule MilosTrainingWeb.Schemas.Coaching do
  @moduledoc "OpenAPI schemas for Phase C coaching (ADR-098)."

  alias OpenApiSpex.{MediaType, RequestBody, Schema}

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_string %Schema{type: :string, nullable: true}
  @date_time %Schema{type: :string, format: :"date-time", nullable: true}

  @review_schema %Schema{
    title: "FormReview",
    type: :object,
    properties: %{
      id: @uuid,
      user_id: @uuid,
      nickname: @nullable_string,
      video_url: %Schema{type: :string},
      note: @nullable_string,
      exercise_name: @nullable_string,
      execution_id: %Schema{type: :string, format: :uuid, nullable: true},
      status: %Schema{type: :string, enum: ["submitted", "reviewed", "withdrawn"]},
      reviewer_id: %Schema{type: :string, format: :uuid, nullable: true},
      feedback: @nullable_string,
      reviewed_at: @date_time,
      inserted_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :user_id, :video_url, :status, :inserted_at]
  }

  @plan_schema %Schema{
    title: "NutritionPlan",
    type: :object,
    nullable: true,
    properties: %{
      id: @uuid,
      user_id: @uuid,
      title: %Schema{type: :string},
      body: %Schema{type: :string},
      daily_calories: %Schema{type: :integer, nullable: true},
      protein_grams: %Schema{type: :integer, nullable: true},
      carbs_grams: %Schema{type: :integer, nullable: true},
      fat_grams: %Schema{type: :integer, nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :user_id, :title, :body]
  }

  def body(schema),
    do: %RequestBody{required: true, content: %{"application/json" => %MediaType{schema: schema}}}

  def reviews_response,
    do: %Schema{
      type: :object,
      properties: %{form_reviews: %Schema{type: :array, items: @review_schema}},
      required: [:form_reviews]
    }

  def review_response,
    do: %Schema{
      type: :object,
      properties: %{form_review: @review_schema},
      required: [:form_review]
    }

  def plan_response,
    do: %Schema{
      type: :object,
      properties: %{nutrition_plan: @plan_schema},
      required: [:nutrition_plan]
    }
end
