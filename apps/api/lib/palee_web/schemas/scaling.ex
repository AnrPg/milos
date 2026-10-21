defmodule PaleeWeb.Schemas.Scaling do
  @moduledoc "OpenAPI schemas for AI scaling suggestions and the gym's AI settings (ADR-174, P3-M12)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @uuid %Schema{type: :string, format: :uuid}
  @date %Schema{type: :string, format: :date}
  @maybe_datetime %Schema{type: :string, format: :"date-time", nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Community.body(schema)

  def change,
    do: %Schema{
      type: :string,
      enum: ~w(substitute load reps skip other),
      description: "substitute: another movement; load/reps/other: a new prescription; skip"
    }

  def status,
    do: %Schema{type: :string, enum: ~w(pending approved dismissed no_change superseded)}

  defp item do
    %Schema{
      title: "ScalingSuggestionItem",
      type: :object,
      properties: %{
        id: %Schema{type: :string},
        exercise_id: %Schema{type: :string},
        section_id: @maybe_string,
        section_name: @maybe_string,
        exercise_name: @maybe_string,
        prescribed: @maybe_string,
        change: change(),
        suggested: @maybe_string,
        reason: %Schema{type: :string}
      },
      required: [:id, :exercise_id, :change, :reason]
    }
  end

  def suggestion do
    %Schema{
      title: "ScalingSuggestion",
      type: :object,
      properties: %{
        id: @uuid,
        athlete_id: @uuid,
        athlete_nickname: @maybe_string,
        assigned_workout_id: @uuid,
        master_workout_id: @uuid,
        workout_title: @maybe_string,
        scheduled_for: @date,
        status: status(),
        summary: @maybe_string,
        scale_level_slug: @maybe_string,
        scale_level_label: @maybe_string,
        injury_regions: %Schema{type: :array, items: %Schema{type: :string}},
        items: %Schema{type: :array, items: item()},
        coach_note: @maybe_string,
        reviewed_at: @maybe_datetime,
        inserted_at: %Schema{type: :string, format: :"date-time"}
      },
      required: [:id, :athlete_id, :master_workout_id, :scheduled_for, :status, :items]
    }
  end

  def queue_response do
    %Schema{
      title: "ScalingSuggestionQueue",
      type: :object,
      properties: %{suggestions: %Schema{type: :array, items: suggestion()}},
      required: [:suggestions]
    }
  end

  def suggestion_response do
    %Schema{
      title: "ScalingSuggestionResponse",
      type: :object,
      properties: %{suggestion: suggestion()},
      required: [:suggestion]
    }
  end

  def approve_request do
    %Schema{
      title: "ScalingSuggestionApproveRequest",
      type: :object,
      additionalProperties: false,
      properties: %{
        items: %Schema{
          type: :array,
          maxItems: 20,
          items: %Schema{
            type: :object,
            additionalProperties: false,
            properties: %{
              id: %Schema{type: :string, maxLength: 10},
              include: %Schema{type: :boolean},
              suggested: %Schema{type: :string, maxLength: 120}
            },
            required: [:id]
          }
        },
        scale_level_slug: %Schema{type: :string, nullable: true, maxLength: 40},
        coach_note: %Schema{type: :string, nullable: true, maxLength: 500}
      }
    }
  end

  def member_response do
    %Schema{
      title: "MyWorkoutScaling",
      type: :object,
      properties: %{
        scaling: %Schema{
          title: "MyWorkoutScalingDetail",
          type: :object,
          nullable: true,
          properties: %{
            id: @uuid,
            scheduled_for: @date,
            scale_level_slug: @maybe_string,
            scale_level_label: @maybe_string,
            coach_note: @maybe_string,
            reviewed_at: @maybe_datetime,
            items: %Schema{
              type: :array,
              items: %Schema{
                title: "MyWorkoutScalingItem",
                type: :object,
                properties: %{
                  exercise_id: %Schema{type: :string},
                  section_id: @maybe_string,
                  exercise_name: @maybe_string,
                  change: change(),
                  suggested: @maybe_string,
                  reason: %Schema{type: :string}
                },
                required: [:exercise_id, :change, :reason]
              }
            },
            modifications: %Schema{
              type: :array,
              description: "ADR-050 modification patches of the approved changes",
              items: %Schema{type: :object, additionalProperties: true}
            }
          },
          required: [:id, :items, :modifications]
        }
      },
      required: [:scaling]
    }
  end

  def ai_settings do
    %Schema{
      title: "GymAiSettings",
      type: :object,
      properties: %{
        provider: %Schema{type: :string, enum: ["anthropic"]},
        scaling_enabled: %Schema{type: :boolean},
        voice_enabled: %Schema{type: :boolean},
        key_configured: %Schema{type: :boolean},
        key_last4: @maybe_string,
        key_status: %Schema{type: :string, enum: ~w(unknown valid rejected)},
        model: @maybe_string,
        default_model: %Schema{type: :string},
        usage: %Schema{
          title: "GymAiUsage",
          type: :object,
          properties: %{
            since: %Schema{type: :string, format: :"date-time"},
            suggestions: %Schema{type: :integer},
            cost_usd: %Schema{type: :number}
          },
          required: [:since, :suggestions, :cost_usd]
        }
      },
      required: [
        :scaling_enabled,
        :voice_enabled,
        :key_configured,
        :key_status,
        :default_model,
        :usage
      ]
    }
  end

  def ai_settings_response do
    %Schema{
      title: "GymAiSettingsResponse",
      type: :object,
      properties: %{ai_settings: ai_settings()},
      required: [:ai_settings]
    }
  end

  def ai_settings_request do
    %Schema{
      title: "GymAiSettingsUpdate",
      type: :object,
      additionalProperties: false,
      properties: %{
        scaling_enabled: %Schema{type: :boolean},
        voice_enabled: %Schema{type: :boolean},
        api_key: %Schema{type: :string, minLength: 20, maxLength: 300, writeOnly: true},
        remove_key: %Schema{type: :boolean},
        model: %Schema{type: :string, nullable: true, maxLength: 80}
      }
    }
  end
end
