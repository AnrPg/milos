defmodule MilosTrainingWeb.Schemas.TrainingLog do
  @moduledoc "OpenAPI schemas for standalone training-log entries (ADR-108)."

  alias OpenApiSpex.Schema

  @source_types ["class", "assigned_workout", "library_workout", "freeform"]

  @section_score %Schema{
    type: :object,
    required: [:section_id, :value],
    properties: %{
      section_id: %Schema{type: :string},
      value: %Schema{oneOf: [%Schema{type: :number}, %Schema{type: :string}]},
      unit: %Schema{type: :string, nullable: true}
    }
  }

  # ADR-050 structured patch shape (see ExecutionController.add_modifications).
  @modification %Schema{
    type: :object,
    required: [:patch_id, :section_id, :field, :canonical_value, :actual_value],
    properties: %{
      patch_id: %Schema{type: :string},
      type: %Schema{type: :string},
      field: %Schema{type: :string},
      section_id: %Schema{type: :string},
      section_name: %Schema{type: :string, nullable: true},
      segment_key: %Schema{type: :string, nullable: true},
      exercise_id: %Schema{type: :string, nullable: true},
      exercise_name: %Schema{type: :string, nullable: true},
      set_index: %Schema{type: :integer, nullable: true},
      round_index: %Schema{type: :integer, nullable: true},
      interval_index: %Schema{type: :integer, nullable: true},
      row_index: %Schema{type: :integer, nullable: true},
      canonical_value: %Schema{
        oneOf: [%Schema{type: :string}, %Schema{type: :number}, %Schema{type: :boolean}]
      },
      actual_value: %Schema{
        oneOf: [%Schema{type: :string}, %Schema{type: :number}, %Schema{type: :boolean}]
      },
      unit: %Schema{type: :string, nullable: true},
      note: %Schema{type: :string, nullable: true}
    }
  }

  @performed_exercise %Schema{
    type: :object,
    required: [:name],
    properties: %{
      row_index: %Schema{type: :integer},
      name: %Schema{type: :string, minLength: 1, maxLength: 120},
      exercise_ref: %Schema{type: :string, nullable: true, maxLength: 120},
      sets: %Schema{type: :integer, nullable: true, minimum: 1, maximum: 100},
      reps: %Schema{type: :integer, nullable: true, minimum: 0},
      load: %Schema{type: :number, nullable: true, minimum: 0},
      load_unit: %Schema{type: :string, nullable: true, enum: ["kg", "lb"]},
      distance: %Schema{type: :number, nullable: true, minimum: 0},
      distance_unit: %Schema{type: :string, nullable: true, enum: ["m", "km", "mi"]},
      duration_seconds: %Schema{type: :integer, nullable: true, minimum: 0},
      calories: %Schema{type: :integer, nullable: true, minimum: 0},
      note: %Schema{type: :string, nullable: true, maxLength: 500}
    }
  }

  @detail_properties %{
    performed_at: %Schema{type: :string, format: :"date-time"},
    timezone: %Schema{type: :string, nullable: true},
    title: %Schema{type: :string, nullable: true, maxLength: 160},
    duration_seconds: %Schema{type: :integer, nullable: true, minimum: 0, maximum: 86_400},
    perceived_effort: %Schema{type: :integer, nullable: true, minimum: 1, maximum: 10},
    notes: %Schema{type: :string, nullable: true, maxLength: 4000},
    scale_level_slug: %Schema{type: :string, nullable: true},
    section_scores: %Schema{type: :array, items: @section_score, maxItems: 50},
    exercise_modifications: %Schema{type: :array, items: @modification},
    performed_exercises: %Schema{type: :array, items: @performed_exercise, maxItems: 50}
  }

  @entry %Schema{
    title: "TrainingLogEntry",
    type: :object,
    required: [
      :id,
      :source_type,
      :title,
      :performed_at_utc,
      :status,
      :lock_version,
      :section_scores,
      :exercise_modifications,
      :performed_exercises
    ],
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      organization_id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      source_type: %Schema{type: :string, enum: @source_types},
      source_reference_id: %Schema{type: :string, format: :uuid, nullable: true},
      master_workout_id: %Schema{type: :string, format: :uuid, nullable: true},
      booking_id: %Schema{type: :string, format: :uuid, nullable: true},
      title: %Schema{type: :string},
      workout_type: %Schema{type: :string, nullable: true},
      scale_level_slug: %Schema{type: :string, nullable: true},
      performed_at_utc: %Schema{type: :string, format: :"date-time"},
      performed_at_tz: %Schema{type: :string},
      duration_seconds: %Schema{type: :integer, nullable: true},
      perceived_effort: %Schema{type: :integer, nullable: true},
      notes: %Schema{type: :string, nullable: true},
      section_scores: %Schema{type: :array, items: @section_score},
      exercise_modifications: %Schema{type: :array, items: @modification},
      performed_exercises: %Schema{type: :array, items: @performed_exercise},
      status: %Schema{type: :string, enum: ["logged", "voided"]},
      voided_at: %Schema{type: :string, format: :"date-time", nullable: true},
      void_reason: %Schema{type: :string, nullable: true},
      idempotency_key: %Schema{type: :string},
      lock_version: %Schema{type: :integer},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    }
  }

  @scoreable_section %Schema{
    type: :object,
    required: [:id],
    properties: %{
      id: %Schema{type: :string},
      name: %Schema{type: :string, nullable: true},
      score_type: %Schema{type: :string, nullable: true},
      unit: %Schema{type: :string, nullable: true}
    }
  }

  def source_types, do: @source_types

  def create_request do
    %Schema{
      title: "TrainingLogCreateRequest",
      type: :object,
      required: [:source_type, :performed_at, :idempotency_key],
      properties:
        Map.merge(@detail_properties, %{
          source_type: %Schema{type: :string, enum: @source_types},
          source_reference_id: %Schema{type: :string, format: :uuid, nullable: true},
          idempotency_key: %Schema{type: :string, minLength: 8, maxLength: 128}
        }),
      additionalProperties: false
    }
  end

  def update_request do
    %Schema{
      title: "TrainingLogUpdateRequest",
      type: :object,
      properties:
        Map.put(@detail_properties, :expected_version, %Schema{type: :integer, minimum: 1}),
      additionalProperties: false
    }
  end

  def void_request do
    %Schema{
      title: "TrainingLogVoidRequest",
      type: :object,
      properties: %{
        reason: %Schema{type: :string, nullable: true, maxLength: 500},
        expected_version: %Schema{type: :integer, minimum: 1}
      },
      additionalProperties: false
    }
  end

  def entry_response do
    %Schema{
      title: "TrainingLogEntryResponse",
      type: :object,
      required: [:entry],
      properties: %{entry: @entry}
    }
  end

  def entry_collection do
    %Schema{
      title: "TrainingLogEntryCollection",
      type: :object,
      required: [:entries],
      properties: %{entries: %Schema{type: :array, items: @entry}}
    }
  end

  def sources_response do
    %Schema{
      title: "TrainingLogSources",
      type: :object,
      required: [:classes, :assignments, :library_workouts],
      properties: %{
        classes: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :title, :scheduled_at, :scoreable_sections],
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              booking_id: %Schema{type: :string, format: :uuid, nullable: true},
              title: %Schema{type: :string},
              scheduled_at: %Schema{type: :string, format: :"date-time"},
              workout_id: %Schema{type: :string, format: :uuid, nullable: true},
              workout_title: %Schema{type: :string, nullable: true},
              scoreable_sections: %Schema{type: :array, items: @scoreable_section}
            }
          }
        },
        assignments: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :title, :scheduled_for, :scoreable_sections],
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              title: %Schema{type: :string},
              scheduled_for: %Schema{type: :string, format: :date},
              workout_id: %Schema{type: :string, format: :uuid, nullable: true},
              workout_title: %Schema{type: :string, nullable: true},
              scoreable_sections: %Schema{type: :array, items: @scoreable_section}
            }
          }
        },
        library_workouts: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            required: [:id, :title],
            properties: %{
              id: %Schema{type: :string, format: :uuid},
              title: %Schema{type: :string},
              workout_type: %Schema{type: :string, nullable: true}
            }
          }
        }
      }
    }
  end
end
