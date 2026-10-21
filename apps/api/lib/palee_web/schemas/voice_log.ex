defmodule PaleeWeb.Schemas.VoiceLog do
  @moduledoc "OpenAPI schemas for voice logging (ADR-175, P3-M13)."

  alias PaleeWeb.Schemas.Community
  alias OpenApiSpex.Schema

  @maybe_int %Schema{type: :integer, nullable: true}
  @maybe_string %Schema{type: :string, nullable: true}

  def body(schema), do: Community.body(schema)

  def availability_response do
    %Schema{
      title: "VoiceLogAvailabilityResponse",
      type: :object,
      properties: %{
        voice: %Schema{
          title: "VoiceLogAvailability",
          type: :object,
          properties: %{
            available: %Schema{type: :boolean},
            enabled: %Schema{type: :boolean},
            max_seconds: %Schema{type: :integer},
            daily_limit: %Schema{type: :integer},
            remaining_today: %Schema{type: :integer}
          },
          required: [:available, :enabled, :max_seconds, :daily_limit, :remaining_today]
        }
      },
      required: [:voice]
    }
  end

  def draft_request do
    %Schema{
      title: "VoiceLogDraftRequest",
      type: :object,
      additionalProperties: false,
      properties: %{
        audio_base64: %Schema{type: :string, minLength: 100, maxLength: 3_400_000},
        mime_type: %Schema{type: :string, maxLength: 80},
        duration_ms: %Schema{type: :integer, minimum: 0, maximum: 600_000},
        locale: %Schema{type: :string, maxLength: 10}
      },
      required: [:audio_base64, :mime_type]
    }
  end

  def draft_response do
    %Schema{
      title: "VoiceLogDraftResponse",
      type: :object,
      properties: %{
        transcript: %Schema{type: :string},
        parsed: %Schema{type: :boolean},
        draft: %Schema{
          title: "VoiceLogDraft",
          type: :object,
          properties: %{
            title: @maybe_string,
            duration_minutes: @maybe_int,
            perceived_effort: @maybe_int,
            days_ago: @maybe_int,
            notes: @maybe_string,
            exercises: %Schema{
              type: :array,
              items: %Schema{
                title: "VoiceLogDraftExercise",
                type: :object,
                properties: %{
                  name: %Schema{type: :string},
                  sets: @maybe_int,
                  reps: @maybe_int,
                  load: %Schema{type: :number, nullable: true},
                  load_unit: %Schema{type: :string, enum: ["kg", "lb"], nullable: true}
                },
                required: [:name, :sets, :reps, :load, :load_unit]
              }
            }
          },
          required: [
            :title,
            :duration_minutes,
            :perceived_effort,
            :days_ago,
            :notes,
            :exercises
          ]
        }
      },
      required: [:transcript, :parsed, :draft]
    }
  end
end
