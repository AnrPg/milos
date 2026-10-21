defmodule MilosTrainingWeb.Schemas.TrainingDepth do
  @moduledoc """
  OpenAPI schemas for the Πρόοδος depth sections (ADR-165): muscle coverage
  summary, qualities radar and training load, for the member and for a
  coach's view of a client. Node ids come from `GET /api/anatomy/taxonomy`,
  quality ids from the same payload.
  """

  alias OpenApiSpex.Schema

  @level %Schema{type: :string, enum: ["none", "low", "medium", "high"]}

  @group %Schema{
    title: "DepthCoverageGroup",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Taxonomy group id"},
      sets: %Schema{type: :number, description: "Weighted sets in the range"},
      per_week: %Schema{type: :number},
      level: @level
    },
    required: [:id, :sets, :per_week, :level]
  }

  @coverage %Schema{
    title: "DepthCoverage",
    type: :object,
    properties: %{
      sessions: %Schema{type: :integer, description: "Workouts done in the range"},
      exercises: %Schema{
        title: "DepthExerciseCounts",
        type: :object,
        properties: %{
          recognized: %Schema{type: :integer},
          unrecognized: %Schema{type: :integer}
        },
        required: [:recognized, :unrecognized]
      },
      felt_entries: %Schema{type: :integer},
      thresholds: %Schema{
        title: "DepthCoverageThresholds",
        type: :object,
        properties: %{medium: %Schema{type: :number}, high: %Schema{type: :number}},
        required: [:medium, :high]
      },
      most: %Schema{
        type: :array,
        items: @group,
        description: "Up to three major groups with the most weighted sets"
      },
      least: %Schema{
        type: :array,
        items: @group,
        description: "Up to three major groups at level none or low, lowest first"
      },
      balance: %Schema{
        title: "DepthBalance",
        type: :object,
        description:
          "Exercise sets by primary muscles; a ratio only once both sides have sets and reach 4 together",
        properties: %{
          push: %Schema{type: :number},
          pull: %Schema{type: :number},
          push_pull_ratio: %Schema{type: :number, nullable: true},
          quad: %Schema{type: :number},
          ham: %Schema{type: :number},
          quad_ham_ratio: %Schema{type: :number, nullable: true}
        },
        required: [:push, :pull, :push_pull_ratio, :quad, :ham, :quad_ham_ratio]
      }
    },
    required: [
      :sessions,
      :exercises,
      :felt_entries,
      :thresholds,
      :most,
      :least,
      :balance
    ]
  }

  @qualities %Schema{
    title: "DepthQualities",
    type: :object,
    properties: %{
      sessions: %Schema{type: :integer, description: "Workouts with a recognised exercise"},
      felt_entries: %Schema{type: :integer},
      qualities: %Schema{
        type: :array,
        description: "All ten qualities, canonical order",
        items: %Schema{
          title: "DepthQuality",
          type: :object,
          properties: %{
            id: %Schema{type: :string},
            sets: %Schema{type: :integer},
            score: %Schema{
              type: :number,
              description: "Share of the most-trained quality, 0..1"
            },
            felt: %Schema{type: :integer}
          },
          required: [:id, :sets, :score, :felt]
        }
      }
    },
    required: [:sessions, :felt_entries, :qualities]
  }

  @load %Schema{
    title: "DepthLoad",
    type: :object,
    description:
      "Session RPE (effort × minutes) as of today: an indicator against the athlete's own usual week, never advice",
    properties: %{
      acute: %Schema{type: :integer, description: "Load of the last 7 days"},
      chronic: %Schema{type: :integer, description: "Weekly average of the last 28 days"},
      ratio: %Schema{type: :number, nullable: true},
      band: %Schema{
        type: :string,
        nullable: true,
        enum: ["below", "steady", "above", "well_above"]
      },
      sufficient: %Schema{type: :boolean},
      rated_sessions: %Schema{type: :integer, description: "Last 28 days, with effort and time"},
      unrated_sessions: %Schema{
        type: :integer,
        description: "Last 28 days, without effort or time (not counted)"
      },
      bands: %Schema{
        title: "DepthLoadBands",
        type: :object,
        properties: %{
          below: %Schema{type: :number},
          steady_to: %Schema{type: :number},
          above_to: %Schema{type: :number}
        },
        required: [:below, :steady_to, :above_to]
      },
      weeks: %Schema{
        type: :array,
        items: %Schema{
          title: "DepthLoadWeek",
          type: :object,
          properties: %{
            week_start: %Schema{type: :string, format: :date},
            load: %Schema{type: :integer},
            sessions: %Schema{type: :integer}
          },
          required: [:week_start, :load, :sessions]
        }
      }
    },
    required: [
      :acute,
      :chronic,
      :ratio,
      :band,
      :sufficient,
      :rated_sessions,
      :unrated_sessions,
      :bands,
      :weeks
    ]
  }

  @properties %{
    range: %Schema{type: :string, enum: ["4w", "12w", "6m", "1y", "all"]},
    from: %Schema{type: :string, format: :date},
    to: %Schema{type: :string, format: :date},
    weeks: %Schema{type: :integer},
    coverage: @coverage,
    qualities: @qualities,
    load: @load
  }

  @required [:range, :from, :to, :weeks, :coverage, :qualities, :load]

  def my_depth_response do
    %Schema{
      title: "MyTrainingDepth",
      type: :object,
      properties:
        Map.put(@properties, :sources, %Schema{
          type: :array,
          items: %Schema{type: :string},
          description: "The source filter applied (none = every source)"
        }),
      required: [:sources | @required]
    }
  end

  def client_depth_response do
    %Schema{
      title: "ClientTrainingDepth",
      type: :object,
      description: "Only from entries the client shares with this gym's coaches",
      properties: @properties,
      required: @required
    }
  end
end
