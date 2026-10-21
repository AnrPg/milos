defmodule MilosTrainingWeb.Schemas.AnatomyAtlas do
  @moduledoc """
  OpenAPI schemas for the anatomy atlas (ADR-164): the member's muscle
  coverage across providers and the gym's exercises for one node. Node ids
  come from `GET /api/anatomy/taxonomy`.
  """

  alias OpenApiSpex.Schema

  @level %Schema{type: :string, enum: ["none", "low", "medium", "high"]}

  @node %Schema{
    title: "AtlasNodeCoverage",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Taxonomy node id (region, group or head)"},
      kind: %Schema{type: :string, enum: ["region", "group", "head"]},
      sets: %Schema{
        type: :number,
        description: "Weighted sets in the range: primary 1, secondary 0.5, stabilizer 0"
      },
      per_week: %Schema{type: :number},
      level: @level,
      felt: %Schema{type: :integer, description: "Entries in the range the member felt it in"},
      top_exercises: %Schema{
        type: :array,
        items: %Schema{
          title: "AtlasTopExercise",
          type: :object,
          properties: %{
            exercise_ref: %Schema{type: :string},
            sets: %Schema{type: :number}
          },
          required: [:exercise_ref, :sets]
        }
      }
    },
    required: [:id, :kind, :sets, :per_week, :level, :felt, :top_exercises]
  }

  def atlas_response do
    %Schema{
      title: "MyAtlas",
      type: :object,
      properties: %{
        range: %Schema{type: :string, enum: ["1w", "4w", "12w"]},
        weeks: %Schema{type: :integer},
        from: %Schema{type: :string, format: :date},
        to: %Schema{type: :string, format: :date},
        taxonomy_version: %Schema{type: :integer},
        thresholds: %Schema{
          title: "AtlasThresholds",
          type: :object,
          description: "Weighted sets per week from which medium and high start; any set is low",
          properties: %{medium: %Schema{type: :number}, high: %Schema{type: :number}},
          required: [:medium, :high]
        },
        sessions: %Schema{type: :integer, description: "Workouts done in the range"},
        felt_entries: %Schema{type: :integer},
        exercises: %Schema{
          title: "AtlasExerciseCounts",
          type: :object,
          properties: %{
            recognized: %Schema{type: :integer},
            unrecognized: %Schema{type: :integer}
          },
          required: [:recognized, :unrecognized]
        },
        nodes: %Schema{
          type: :array,
          items: @node,
          description: "Only nodes with sets or felt entries, in tree order"
        }
      },
      required: [
        :range,
        :weeks,
        :from,
        :to,
        :taxonomy_version,
        :thresholds,
        :sessions,
        :felt_entries,
        :exercises,
        :nodes
      ]
    }
  end

  def node_exercises_response do
    %Schema{
      title: "AtlasNodeExercises",
      type: :object,
      properties: %{
        node_id: %Schema{type: :string},
        videos_included: %Schema{
          type: :boolean,
          description: "False when the member's package does not include on-demand videos"
        },
        exercises: %Schema{
          type: :array,
          items: %Schema{
            title: "AtlasNodeExercise",
            type: :object,
            properties: %{
              exercise_ref: %Schema{type: :string},
              label: %Schema{type: :string},
              role: %Schema{type: :string, enum: ["primary", "secondary"]},
              videos: %Schema{
                type: :array,
                items: %Schema{
                  title: "AtlasExerciseVideo",
                  type: :object,
                  properties: %{
                    id: %Schema{type: :string, format: :uuid},
                    title: %Schema{type: :string},
                    video_url: %Schema{type: :string},
                    duration_minutes: %Schema{type: :integer, nullable: true}
                  },
                  required: [:id, :title, :video_url, :duration_minutes]
                }
              }
            },
            required: [:exercise_ref, :label, :role, :videos]
          }
        }
      },
      required: [:node_id, :videos_included, :exercises]
    }
  end
end
