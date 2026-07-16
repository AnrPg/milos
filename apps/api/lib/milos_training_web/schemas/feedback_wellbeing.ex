defmodule MilosTrainingWeb.Schemas.FeedbackWellbeing do
  alias OpenApiSpex.Schema

  @review_answer %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      review_id: %Schema{type: :string, format: :uuid},
      question_key: %Schema{type: :string},
      question_text: %Schema{type: :string},
      answer_text: %Schema{type: :string},
      rating_value: %Schema{type: :integer, minimum: 1, maximum: 5, nullable: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :review_id,
      :question_key,
      :question_text,
      :answer_text,
      :inserted_at,
      :updated_at
    ],
    additionalProperties: false
  }

  @review %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
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
      target_snapshot: %Schema{type: :object, additionalProperties: true},
      questionnaire_id: %Schema{type: :string, format: :uuid, nullable: true},
      rating: %Schema{type: :integer, minimum: 1, maximum: 5, nullable: true},
      sentiment: %Schema{type: :string, enum: ["positive", "neutral", "negative", "mixed"]},
      visibility: %Schema{type: :string, enum: ["admin_only", "user_visible"]},
      body: %Schema{type: :string, nullable: true},
      status: %Schema{
        type: :string,
        enum: ["open", "reviewed", "archived", "needs_follow_up"]
      },
      tags: %Schema{type: :array, items: %Schema{type: :string}},
      params: %Schema{type: :object, additionalProperties: true},
      answers: %Schema{type: :array, items: @review_answer},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :target_type,
      :target_snapshot,
      :sentiment,
      :visibility,
      :status,
      :tags,
      :params,
      :answers,
      :inserted_at,
      :updated_at
    ],
    additionalProperties: false
  }

  @injury %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      reported_by_id: %Schema{type: :string, format: :uuid},
      reported_by_role: %Schema{type: :string, enum: ["self", "admin"]},
      body_area: %Schema{type: :string},
      severity: %Schema{type: :string, enum: ["mild", "moderate", "severe"]},
      status: %Schema{type: :string, enum: ["active", "healed"]},
      started_on: %Schema{type: :string, format: :date, nullable: true},
      healed_on: %Schema{type: :string, format: :date, nullable: true},
      description: %Schema{type: :string, nullable: true},
      training_limitations: %Schema{type: :string, nullable: true},
      tags: %Schema{type: :array, items: %Schema{type: :string}},
      visibility: %Schema{type: :string, enum: ["admin_only", "user_and_admin"]},
      params: %Schema{type: :object, additionalProperties: true},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :reported_by_id,
      :reported_by_role,
      :body_area,
      :severity,
      :status,
      :tags,
      :visibility,
      :params,
      :inserted_at,
      :updated_at
    ],
    additionalProperties: false
  }

  def review, do: @review
  def review_collection, do: collection(:reviews, @review)
  def review_response, do: item(:review, @review)

  def injury, do: @injury
  def injury_collection, do: collection(:injuries, @injury)
  def injury_response, do: item(:injury, @injury)

  defp collection(key, schema) do
    %Schema{
      type: :object,
      properties: %{key => %Schema{type: :array, items: schema}},
      required: [key],
      additionalProperties: false
    }
  end

  defp item(key, schema) do
    %Schema{
      type: :object,
      properties: %{key => schema},
      required: [key],
      additionalProperties: false
    }
  end
end
