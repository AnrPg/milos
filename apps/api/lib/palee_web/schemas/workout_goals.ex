defmodule PaleeWeb.Schemas.WorkoutGoals do
  @moduledoc """
  OpenAPI schemas for WOD goals, «τι ένιωσες» feedback and the static
  anatomy taxonomy (ADR-163). Muscle and quality ids come from
  `GET /api/anatomy/taxonomy`; the server rejects ids outside it.
  """

  alias OpenApiSpex.Schema

  @role %Schema{type: :string, enum: ["primary", "secondary", "stabilizer"]}

  @muscle %Schema{
    title: "GoalMuscle",
    type: :object,
    properties: %{
      id: %Schema{type: :string, description: "Taxonomy group or head id"},
      role: @role
    },
    required: [:id, :role],
    additionalProperties: false
  }

  @ids %Schema{type: :array, items: %Schema{type: :string}}

  @staff_goals %Schema{
    title: "StaffWorkoutGoals",
    type: :object,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      saved: %Schema{
        type: :boolean,
        description:
          "False when this workout has no goals of its own: these are inherited (inherited_from) or the live suggestion"
      },
      inherited_from: %Schema{
        type: :string,
        format: :uuid,
        nullable: true,
        description:
          "The workout these goals are inherited from (this one is a class variant or copy without goals of its own); a save gives this workout its own"
      },
      muscles: %Schema{type: :array, items: @muscle},
      qualities: @ids,
      stimulus: %Schema{type: :string, nullable: true},
      visible_to_members: %Schema{type: :boolean},
      source: %Schema{type: :string, enum: ["suggested", "edited"]},
      taxonomy_version: %Schema{type: :integer},
      updated_by_id: %Schema{type: :string, format: :uuid, nullable: true},
      updated_at: %Schema{type: :string, format: :"date-time", nullable: true}
    },
    required: [
      :workout_id,
      :saved,
      :inherited_from,
      :muscles,
      :qualities,
      :stimulus,
      :visible_to_members,
      :source,
      :taxonomy_version,
      :updated_by_id,
      :updated_at
    ],
    additionalProperties: false
  }

  @suggestion %Schema{
    title: "WorkoutGoalSuggestion",
    type: :object,
    properties: %{
      muscles: %Schema{type: :array, items: @muscle},
      qualities: @ids,
      matched_exercises: %Schema{type: :integer, minimum: 0},
      unmatched_exercises: %Schema{type: :integer, minimum: 0},
      taxonomy_version: %Schema{type: :integer}
    },
    required: [
      :muscles,
      :qualities,
      :matched_exercises,
      :unmatched_exercises,
      :taxonomy_version
    ],
    additionalProperties: false
  }

  @staff_response %Schema{
    title: "StaffWorkoutGoalsResponse",
    type: :object,
    properties: %{goals: @staff_goals, suggestion: @suggestion},
    required: [:goals, :suggestion],
    additionalProperties: false
  }

  @save_request %Schema{
    title: "SaveWorkoutGoalsRequest",
    type: :object,
    properties: %{
      muscles: %Schema{type: :array, items: @muscle, maxItems: 40},
      qualities: @ids,
      stimulus: %Schema{type: :string, nullable: true, maxLength: 280},
      visible_to_members: %Schema{
        type: :boolean,
        description:
          "Left out: keep the saved value; a first save takes the inherited goals' value, else the gym's wod_goals_visible_by_default"
      }
    },
    required: [:muscles, :qualities]
  }

  @member_goals %Schema{
    title: "MemberWorkoutGoals",
    type: :object,
    nullable: true,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      muscles: %Schema{type: :array, items: @muscle},
      qualities: @ids,
      stimulus: %Schema{type: :string, nullable: true},
      taxonomy_version: %Schema{type: :integer},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:workout_id, :muscles, :qualities, :stimulus, :taxonomy_version, :updated_at],
    additionalProperties: false
  }

  @member_response %Schema{
    title: "MemberWorkoutGoalsResponse",
    type: :object,
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid},
      goals: @member_goals
    },
    required: [:workout_id, :goals],
    additionalProperties: false
  }

  @feedback %Schema{
    title: "GoalFeedback",
    type: :object,
    nullable: true,
    properties: %{
      felt_muscles: @ids,
      felt_qualities: @ids,
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:felt_muscles, :felt_qualities, :updated_at],
    additionalProperties: false
  }

  @feedback_response %Schema{
    title: "GoalFeedbackResponse",
    type: :object,
    properties: %{
      entry_kind: %Schema{type: :string, enum: ["execution", "training_log"]},
      entry_id: %Schema{type: :string, format: :uuid},
      voided: %Schema{type: :boolean},
      goals: @member_goals,
      feedback: @feedback
    },
    required: [:entry_kind, :entry_id, :voided, :goals, :feedback],
    additionalProperties: false
  }

  @feedback_request %Schema{
    title: "SaveGoalFeedbackRequest",
    type: :object,
    properties: %{
      felt_muscles: %Schema{type: :array, items: %Schema{type: :string}, maxItems: 40},
      felt_qualities: @ids
    },
    required: [:felt_muscles, :felt_qualities]
  }

  @count %Schema{
    title: "GoalFeedbackCount",
    type: :object,
    properties: %{id: %Schema{type: :string}, count: %Schema{type: :integer, minimum: 1}},
    required: [:id, :count],
    additionalProperties: false
  }

  @feedback_summary %Schema{
    title: "GoalFeedbackSummary",
    type: :object,
    description:
      "Coach totals of «τι ένιωσες» over the entries the caller may read (non-voided). Lists are empty and shown is false below 3 entries.",
    properties: %{
      workout_id: %Schema{type: :string, format: :uuid, nullable: true},
      scheduled_class_id: %Schema{
        type: :string,
        format: :uuid,
        description: "Only on the scheduled-class summary"
      },
      entries: %Schema{type: :integer, minimum: 0},
      shown: %Schema{type: :boolean},
      felt_muscles: %Schema{
        type: :array,
        items: @count,
        description: "Muscle groups (heads rolled up), most felt first"
      },
      felt_qualities: %Schema{type: :array, items: @count, description: "Most felt first"},
      goals_not_felt: %Schema{
        type: :array,
        items: %Schema{type: :string},
        description: "Groups of the goal's primary and secondary muscles nobody felt"
      }
    },
    required: [:workout_id, :entries, :shown, :felt_muscles, :felt_qualities, :goals_not_felt],
    additionalProperties: false
  }

  @node %Schema{
    title: "AnatomyNode",
    type: :object,
    properties: %{
      id: %Schema{type: :string},
      kind: %Schema{type: :string, enum: ["region", "group", "head"]},
      parent_id: %Schema{type: :string, nullable: true},
      name: %Schema{type: :string, description: "English reference name"},
      ta2_ids: @ids
    },
    required: [:id, :kind, :parent_id, :name, :ta2_ids],
    additionalProperties: false
  }

  @taxonomy %Schema{
    title: "AnatomyTaxonomy",
    type: :object,
    properties: %{
      version: %Schema{type: :integer},
      nodes: %Schema{
        type: :array,
        items: @node,
        description: "Tree order: each region, then its groups, each followed by its heads"
      },
      qualities: @ids,
      roles: %Schema{type: :array, items: @role}
    },
    required: [:version, :nodes, :qualities, :roles],
    additionalProperties: false
  }

  def staff_response, do: @staff_response
  def save_request, do: @save_request
  def member_response, do: @member_response
  def feedback_response, do: @feedback_response
  def feedback_request, do: @feedback_request
  def taxonomy, do: @taxonomy
  def feedback_summary, do: @feedback_summary
end
