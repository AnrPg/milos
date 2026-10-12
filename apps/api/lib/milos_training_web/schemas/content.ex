defmodule MilosTrainingWeb.Schemas.Content do
  @moduledoc "OpenAPI schemas for on-demand video and progress statistics (ADR-098)."

  alias OpenApiSpex.Schema

  @date_time %Schema{type: :string, format: :"date-time", nullable: true}

  def video_schema do
    %Schema{
      title: "ContentVideo",
      type: :object,
      properties: %{
        id: %Schema{type: :string, format: :uuid},
        title: %Schema{type: :string},
        description: %Schema{type: :string, nullable: true},
        video_url: %Schema{type: :string},
        duration_minutes: %Schema{type: :integer, nullable: true},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        published_at: @date_time,
        archived_at: @date_time
      },
      required: [:id, :title, :video_url, :tags, :published_at, :archived_at]
    }
  end

  def video_params_schema do
    %Schema{
      type: :object,
      additionalProperties: false,
      properties: %{
        title: %Schema{type: :string, minLength: 2, maxLength: 120},
        description: %Schema{type: :string, maxLength: 2000, nullable: true},
        video_url: %Schema{type: :string, maxLength: 2000},
        duration_minutes: %Schema{type: :integer, minimum: 1, maximum: 600, nullable: true},
        tags: %Schema{type: :array, items: %Schema{type: :string, maxLength: 40}, maxItems: 8}
      }
    }
  end

  def progress_schema do
    week = %Schema{
      type: :object,
      properties: %{
        week_start: %Schema{type: :string, format: :date},
        sessions: %Schema{type: :integer},
        minutes: %Schema{type: :integer}
      },
      required: [:week_start, :sessions, :minutes]
    }

    point = %Schema{
      type: :object,
      properties: %{
        execution_id: %Schema{type: :string, format: :uuid},
        completed_on: %Schema{type: :string, format: :date},
        value: %Schema{oneOf: [%Schema{type: :number}, %Schema{type: :string}]}
      },
      required: [:execution_id, :completed_on, :value]
    }

    %Schema{
      title: "ProgressStats",
      type: :object,
      properties: %{
        totals: %Schema{
          type: :object,
          properties: %{
            sessions: %Schema{type: :integer},
            minutes: %Schema{type: :integer},
            workouts: %Schema{type: :integer}
          },
          required: [:sessions, :minutes, :workouts]
        },
        weekly: %Schema{type: :array, items: week},
        consistency: %Schema{
          type: :object,
          properties: %{
            weeks: %Schema{type: :integer},
            active_weeks: %Schema{type: :integer},
            percent: %Schema{type: :integer},
            current_streak_weeks: %Schema{type: :integer}
          },
          required: [:weeks, :active_weeks, :percent, :current_streak_weeks]
        },
        sources: %Schema{type: :object, additionalProperties: %Schema{type: :integer}},
        score_history: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              workout_id: %Schema{type: :string, format: :uuid},
              workout_title: %Schema{type: :string, nullable: true},
              section_id: %Schema{type: :string, nullable: true},
              section_name: %Schema{type: :string, nullable: true},
              unit: %Schema{type: :string, nullable: true},
              points: %Schema{type: :array, items: point}
            },
            required: [:workout_id, :points]
          }
        }
      },
      required: [:totals, :weekly, :consistency, :sources, :score_history]
    }
  end
end
