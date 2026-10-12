defmodule MilosTrainingWeb.Schemas.InjuryWarnings do
  @moduledoc """
  OpenAPI schemas for ADR-124 injury-aware workout safety warnings. Warnings
  are informational: no endpoint here blocks an assignment, booking or
  execution.
  """

  alias OpenApiSpex.Schema

  @level %Schema{type: :string, enum: ["none", "caution", "avoid"]}
  @regions ~w(shoulder elbow wrist neck back hip knee hamstring ankle chest core)
  @staff_surfaces ~w(assign_dialog class_roster member_dossier)
  @self_surfaces ~w(assignment_detail class_detail pre_start)

  @exercise %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      exercise_ref: %Schema{type: :string, nullable: true},
      level: %Schema{type: :string, enum: ["caution", "avoid"]},
      patterns: %Schema{type: :array, items: %Schema{type: :string}},
      match: %Schema{type: :string, enum: ["catalog", "name"]}
    },
    required: [:name, :level, :patterns, :match],
    additionalProperties: false
  }

  @warning %Schema{
    type: :object,
    properties: %{
      injury_id: %Schema{type: :string, format: :uuid},
      user_id: %Schema{type: :string, format: :uuid},
      body_area: %Schema{type: :string},
      regions: %Schema{type: :array, items: %Schema{type: :string, enum: @regions}},
      severity: %Schema{type: :string, enum: ["mild", "moderate", "severe"]},
      level: %Schema{type: :string, enum: ["caution", "avoid"]},
      provenance: %Schema{type: :string, enum: ["organization", "personal"]},
      training_limitations: %Schema{type: :string, nullable: true},
      tags: %Schema{type: :array, items: %Schema{type: :string}},
      exercises: %Schema{type: :array, items: @exercise}
    },
    required: [
      :injury_id,
      :user_id,
      :body_area,
      :regions,
      :severity,
      :level,
      :provenance,
      :tags,
      :exercises
    ],
    additionalProperties: false
  }

  @athlete %Schema{
    type: :object,
    properties: %{
      user_id: %Schema{type: :string, format: :uuid},
      level: @level,
      warnings: %Schema{type: :array, items: @warning}
    },
    required: [:user_id, :level, :warnings],
    additionalProperties: false
  }

  @staff_result %Schema{
    title: "AthleteInjuryWarnings",
    type: :object,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      level: @level,
      athletes: %Schema{type: :array, items: @athlete}
    },
    required: [:workout_id, :level, :athletes],
    additionalProperties: false
  }

  @slot_result %Schema{
    title: "ClassSlotInjuryWarnings",
    type: :object,
    properties: %{
      slot_id: %Schema{type: :string, format: :uuid},
      workout_id: %Schema{type: :string, format: :uuid, nullable: true},
      level: @level,
      athletes: %Schema{type: :array, items: @athlete}
    },
    required: [:slot_id, :level, :athletes],
    additionalProperties: false
  }

  @self_result %Schema{
    title: "MyWorkoutInjuryWarnings",
    type: :object,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      level: @level,
      warnings: %Schema{type: :array, items: @warning}
    },
    required: [:workout_id, :level, :warnings],
    additionalProperties: false
  }

  @staff_request %Schema{
    title: "AthleteInjuryWarningsRequest",
    type: :object,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      user_ids: %Schema{
        type: :array,
        items: %Schema{type: :string, format: :uuid},
        maxItems: 250
      },
      surface: %Schema{type: :string, enum: @staff_surfaces, nullable: true},
      source_context_id: %Schema{type: :string, format: :uuid, nullable: true}
    },
    required: [:workout_id, :user_ids],
    additionalProperties: false
  }

  @self_ack_request %Schema{
    title: "MyInjuryWarningsAcknowledgement",
    type: :object,
    properties: %{
      surface: %Schema{type: :string, enum: @self_surfaces, nullable: true},
      source_context_id: %Schema{type: :string, format: :uuid, nullable: true}
    },
    additionalProperties: false
  }

  @staff_ack %Schema{
    title: "AthleteInjuryWarningsAcknowledged",
    type: :object,
    properties: %{acknowledged_count: %Schema{type: :integer, minimum: 0}},
    required: [:acknowledged_count],
    additionalProperties: false
  }

  @self_ack %Schema{
    title: "MyInjuryWarningsAcknowledged",
    type: :object,
    properties: %{level: @level, warning_count: %Schema{type: :integer, minimum: 0}},
    required: [:level, :warning_count],
    additionalProperties: false
  }

  def staff_surfaces, do: @staff_surfaces
  def self_surfaces, do: @self_surfaces
  def staff_result, do: @staff_result
  def slot_result, do: @slot_result
  def self_result, do: @self_result
  def staff_request, do: @staff_request
  def self_ack_request, do: @self_ack_request
  def staff_ack, do: @staff_ack
  def self_ack, do: @self_ack
end
