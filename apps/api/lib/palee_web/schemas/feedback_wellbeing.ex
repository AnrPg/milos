defmodule PaleeWeb.Schemas.FeedbackWellbeing do
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

  # ADR-140 §3: the injury's timeline, oldest first.
  @injury_change %Schema{
    type: :object,
    properties: %{
      field: %Schema{type: :string},
      from: %Schema{nullable: true},
      to: %Schema{nullable: true}
    },
    required: [:field, :from, :to]
  }

  @injury_event %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      event_type: %Schema{
        type: :string,
        enum: ["reported", "updated", "marked_healed", "reopened"]
      },
      actor_id: %Schema{type: :string, format: :uuid, nullable: true},
      occurred_at: %Schema{type: :string, format: :"date-time"},
      payload: %Schema{
        type: :object,
        properties: %{
          note: %Schema{type: :string, nullable: true},
          changes: %Schema{type: :array, items: @injury_change}
        },
        additionalProperties: true
      }
    },
    required: [:id, :event_type, :actor_id, :occurred_at, :payload],
    additionalProperties: false
  }

  @injury %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      organization_id: %Schema{type: :string, format: :uuid, nullable: true},
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
      # ADR-286: a member's own report reaches their boxes while on.
      shared_with_box: %Schema{type: :boolean},
      # ADR-286, staff reads: the member filed it in the app and keeps it.
      owned_by_member: %Schema{type: :boolean},
      params: %Schema{type: :object, additionalProperties: true},
      events: %Schema{type: :array, items: @injury_event},
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
      :events,
      :inserted_at,
      :updated_at
    ],
    additionalProperties: false
  }

  # ADR-140 §2 Πώς νιώθω.
  @check_in_answer %Schema{
    type: :object,
    properties: %{
      question_key: %Schema{type: :string},
      value: %Schema{type: :integer, minimum: 1, maximum: 4},
      note: %Schema{type: :string, nullable: true}
    },
    required: [:question_key, :value, :note],
    additionalProperties: false
  }

  @check_in %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      organization_id: %Schema{type: :string, format: :uuid, nullable: true},
      recorded_at: %Schema{type: :string, format: :"date-time"},
      recorded_tz: %Schema{type: :string},
      journal_visibility: %Schema{
        type: :string,
        enum: ["private", "coach_can_view", "coach_reply_requested", "posted"]
      },
      answers: %Schema{type: :array, items: @check_in_answer},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [
      :id,
      :user_id,
      :organization_id,
      :recorded_at,
      :recorded_tz,
      :journal_visibility,
      :answers,
      :inserted_at,
      :updated_at
    ],
    additionalProperties: false
  }

  @check_in_question %Schema{
    type: :object,
    properties: %{
      key: %Schema{type: :string},
      min: %Schema{type: :integer},
      max: %Schema{type: :integer}
    },
    required: [:key, :min, :max],
    additionalProperties: false
  }

  def check_in_response, do: item(:check_in, @check_in)

  def check_in_timeline do
    %Schema{
      type: :object,
      properties: %{
        questions: %Schema{type: :array, items: @check_in_question},
        check_ins: %Schema{type: :array, items: @check_in}
      },
      required: [:questions, :check_ins],
      additionalProperties: false
    }
  end

  def check_in_request do
    %Schema{
      type: :object,
      properties: %{
        organization_slug: %Schema{type: :string, nullable: true},
        recorded_tz: %Schema{type: :string, nullable: true},
        answers: %Schema{
          type: :array,
          minItems: 1,
          items: %Schema{
            type: :object,
            properties: %{
              question_key: %Schema{type: :string},
              value: %Schema{type: :integer, minimum: 1, maximum: 4},
              note: %Schema{type: :string, nullable: true, maxLength: 1000}
            },
            required: [:question_key, :value],
            additionalProperties: false
          }
        }
      },
      required: [:answers],
      additionalProperties: false
    }
  end

  def review, do: @review
  def review_collection, do: collection(:reviews, @review)
  def review_response, do: item(:review, @review)

  def injury, do: @injury
  def injury_collection, do: collection(:injuries, @injury)
  def injury_response, do: item(:injury, @injury)

  @doc "ADR-286: who of your boxes' staff read your injuries."
  def injury_access_log_response do
    uuid = %Schema{type: :string, format: :uuid}

    %Schema{
      title: "InjuryAccessLog",
      type: :object,
      required: [:entries],
      properties: %{
        entries: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :read_at, :surface, :injury_ids, :reader, :organization],
            properties: %{
              id: uuid,
              read_at: %Schema{type: :string, format: :"date-time"},
              surface: %Schema{type: :string, enum: ~w(profile box_list safety_warning)},
              injury_ids: %Schema{type: :array, items: uuid},
              reader: %Schema{
                type: :object,
                properties: %{
                  id: %Schema{type: :string, format: :uuid, nullable: true},
                  nickname: %Schema{type: :string, nullable: true}
                }
              },
              organization: %Schema{
                type: :object,
                properties: %{id: uuid, name: %Schema{type: :string, nullable: true}}
              }
            }
          }
        }
      }
    }
  end

  def injury_update_request do
    %Schema{
      type: :object,
      properties: %{
        note: %Schema{type: :string, nullable: true, maxLength: 2000},
        severity: %Schema{type: :string, enum: ["mild", "moderate", "severe"]},
        body_area: %Schema{type: :string},
        training_limitations: %Schema{type: :string, nullable: true},
        description: %Schema{type: :string, nullable: true},
        tags: %Schema{type: :array, items: %Schema{type: :string}}
      },
      additionalProperties: false
    }
  end

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
