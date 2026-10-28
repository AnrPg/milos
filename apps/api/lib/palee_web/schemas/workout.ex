defmodule PaleeWeb.Schemas.Workout do
  @moduledoc false

  alias OpenApiSpex.Schema
  alias Palee.Workouts.Domain.WorkoutContent

  @uuid %Schema{type: :string, format: :uuid}
  @nullable_uuid %Schema{type: :string, format: :uuid, nullable: true}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_integer %Schema{type: :integer, nullable: true}
  @nullable_number %Schema{type: :number, nullable: true}
  @prescription_unit %Schema{
    type: :string,
    enum: ["reps", "secs", "kcal", "meters"],
    nullable: true
  }
  @load_mode %Schema{
    type: :string,
    enum: ["absolute", "pct_1rm", "bw"],
    nullable: true
  }

  def set_prescription_schema do
    %Schema{
      type: :object,
      properties: %{
        set_index: %Schema{type: :integer, minimum: 1},
        prescription_value: @nullable_integer,
        prescription_unit: @prescription_unit,
        load_value: @nullable_number,
        load_mode: @load_mode,
        note: @nullable_string,
        metadata: %Schema{type: :object, additionalProperties: true}
      },
      required: [:set_index],
      additionalProperties: false
    }
  end

  def load_progression_schema do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        mode: %Schema{type: :string, enum: ["linear", "per_set"]},
        direction: %Schema{type: :string, enum: ["increase", "decrease"]},
        start_value: %Schema{type: :number, minimum: 0},
        start_mode: %Schema{type: :string, enum: ["absolute", "pct_1rm", "bw"]},
        step_value: %Schema{type: :number, minimum: 0},
        per_set_values: %Schema{
          type: :array,
          items: %Schema{type: :number, minimum: 0, nullable: true}
        }
      },
      required: [
        :mode,
        :direction,
        :start_value,
        :start_mode,
        :step_value,
        :per_set_values
      ],
      additionalProperties: false
    }
  end

  def variation_schema do
    %Schema{
      type: :object,
      properties: %{
        id: @nullable_uuid,
        scale_level_slug: @nullable_string,
        scale_level: scale_level_schema(),
        exercise_name_override: @nullable_string,
        sets: @nullable_integer,
        set_prescriptions: %Schema{
          type: :array,
          items: set_prescription_schema(),
          nullable: true
        },
        prescription_value: @nullable_integer,
        prescription_unit: @prescription_unit,
        load_value: @nullable_integer,
        load_mode: @load_mode,
        load_progression: load_progression_schema(),
        excluded: %Schema{type: :boolean},
        note: @nullable_string,
        content: %Schema{type: :array, items: content_entry_schema()},
        prescription_metadata: %Schema{type: :object, additionalProperties: true}
      },
      additionalProperties: false
    }
  end

  def workout_item_schema do
    %Schema{
      type: :object,
      properties: %{
        id: @nullable_uuid,
        item_type: %Schema{type: :string, enum: ["exercise", "header"], default: "exercise"},
        name: %Schema{type: :string},
        subtitle: @nullable_string,
        exercise_ref: @nullable_string,
        description: @nullable_string,
        order: %Schema{type: :integer, minimum: 1},
        sets: @nullable_integer,
        set_prescriptions: %Schema{type: :array, items: set_prescription_schema()},
        prescription_value: @nullable_integer,
        prescription_unit: @prescription_unit,
        prescription_step: @nullable_integer,
        is_bodyweight: %Schema{type: :boolean},
        load_value: @nullable_integer,
        load_mode: @load_mode,
        load_progression: load_progression_schema(),
        superset_group_id: @nullable_uuid,
        alternating_group_id: @nullable_uuid,
        interval_assignment: @nullable_integer,
        hr_zone: @nullable_integer,
        tempo: @nullable_string,
        rest_seconds: @nullable_integer,
        cluster_rest_seconds: @nullable_integer,
        rest_pause_seconds: @nullable_integer,
        pacing: @nullable_integer,
        note: @nullable_string,
        content: %Schema{type: :array, items: content_entry_schema()},
        prescription_metadata: %Schema{type: :object, additionalProperties: true},
        group_config: %Schema{type: :object, nullable: true, additionalProperties: true},
        excluded: %Schema{type: :boolean},
        variations: %Schema{type: :array, items: variation_schema()},
        applied_variation: %Schema{allOf: [variation_schema()], nullable: true}
      },
      required: [:name],
      additionalProperties: false
    }
  end

  def section_schema(child_depth \\ 1) do
    child_schema =
      if child_depth > 0 do
        section_schema(child_depth - 1)
      else
        %Schema{type: :object, additionalProperties: true}
      end

    %Schema{
      type: :object,
      properties: %{
        id: @nullable_uuid,
        parent_section_id: @nullable_uuid,
        name: %Schema{type: :string},
        subtitle: @nullable_string,
        order: %Schema{type: :integer, minimum: 1},
        scoreable: %Schema{type: :boolean},
        score_config: %Schema{type: :object, nullable: true, additionalProperties: true},
        timer_config: %Schema{type: :object, nullable: true, additionalProperties: true},
        rest_after_seconds: @nullable_integer,
        rest_before_next_section_seconds: @nullable_integer,
        note: @nullable_string,
        content: %Schema{type: :array, items: content_entry_schema()},
        section_metadata: %Schema{type: :object, additionalProperties: true},
        free_text_body: %Schema{
          type: :string,
          nullable: true,
          maxLength: 20_000,
          description: "ADR-180: a text section's text (sectioned workouts)"
        },
        free_text_document: %Schema{type: :object, additionalProperties: true, nullable: true},
        timer_preset: section_timer_preset_schema(),
        exercises: %Schema{type: :array, items: workout_item_schema()},
        sections: %Schema{type: :array, items: child_schema}
      },
      required: [:name, :exercises],
      additionalProperties: false
    }
  end

  @doc "ADR-180: the timer a coach picked for one text section (the free-text preset shape)."
  def section_timer_preset_schema do
    %Schema{
      title: "SectionTimerPreset",
      type: :object,
      nullable: true,
      properties: %{
        format: %Schema{
          type: :string,
          enum: ~w(untimed for_time amrap emom tabata custom_hiit death_by)
        },
        duration_seconds: @nullable_integer,
        rounds: @nullable_integer,
        work_seconds: @nullable_integer,
        rest_seconds: @nullable_integer,
        interval_seconds: @nullable_integer
      },
      required: [:format]
    }
  end

  def draft_request_schema do
    %Schema{
      type: :object,
      properties: %{
        title: @nullable_string,
        type: %Schema{
          type: :string,
          enum: Enum.map(Palee.Workouts.supported_workout_types(), &to_string/1),
          nullable: true
        },
        is_team_workout: %Schema{type: :boolean},
        subtitle: @nullable_string,
        description: @nullable_string,
        difficulty: %Schema{
          type: :string,
          enum: ["beginner", "intermediate", "advanced", "all-levels"],
          nullable: true
        },
        estimated_duration_seconds: @nullable_integer,
        equipment: %Schema{type: :array, items: %Schema{type: :string}},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        content: %Schema{type: :array, items: content_entry_schema()},
        workout_metadata: %Schema{type: :object, additionalProperties: true},
        draft_data: %Schema{type: :object, additionalProperties: true, nullable: true},
        sections: %Schema{type: :array, items: section_schema()},
        editor_session_id: @nullable_uuid,
        authoring_mode: %Schema{
          type: :string,
          enum: Palee.Workouts.authoring_modes(),
          nullable: true
        },
        dsl_version: %Schema{type: :integer, enum: [1], nullable: true},
        dsl_source: %Schema{type: :string, maxLength: 200_000, nullable: true},
        dsl_document: %Schema{type: :object, additionalProperties: true, nullable: true},
        expected_source_revision: %Schema{type: :integer, minimum: 0, nullable: true},
        last_dsl_diagnostics: %Schema{
          type: :array,
          items: PaleeWeb.Schemas.WorkoutDsl.diagnostic_schema()
        },
        free_text_body: %Schema{type: :string, maxLength: 200_000, nullable: true},
        free_text_document: %Schema{type: :object, additionalProperties: true, nullable: true}
      },
      additionalProperties: false
    }
  end

  def workout_schema do
    %Schema{
      type: :object,
      properties: %{
        id: @uuid,
        title: %Schema{type: :string},
        type: %Schema{type: :string},
        status: %Schema{type: :string, enum: ["draft", "published"]},
        is_team_workout: %Schema{type: :boolean},
        subtitle: @nullable_string,
        description: @nullable_string,
        difficulty: @nullable_string,
        estimated_duration_seconds: @nullable_integer,
        equipment: %Schema{type: :array, items: %Schema{type: :string}},
        tags: %Schema{type: :array, items: %Schema{type: :string}},
        content: %Schema{type: :array, items: content_entry_schema()},
        workout_metadata: %Schema{type: :object, additionalProperties: true},
        created_by_id: @nullable_uuid,
        inserted_at: %Schema{type: :string, format: :"date-time", nullable: true},
        updated_at: %Schema{type: :string, format: :"date-time", nullable: true},
        scale_level: scale_level_schema(),
        available_scale_levels: %Schema{type: :array, items: scale_level_schema()},
        sections: %Schema{type: :array, items: section_schema()},
        draft_data: %Schema{type: :object, nullable: true, additionalProperties: true},
        authoring_mode: %Schema{type: :string, enum: Palee.Workouts.authoring_modes()},
        dsl_version: %Schema{type: :integer, enum: [1], nullable: true},
        dsl_source: %Schema{type: :string, nullable: true},
        dsl_document: %Schema{type: :object, additionalProperties: true, nullable: true},
        dsl_source_revision: %Schema{type: :integer, minimum: 0},
        last_dsl_diagnostics: %Schema{
          type: :array,
          items: PaleeWeb.Schemas.WorkoutDsl.diagnostic_schema()
        },
        free_text_body: %Schema{type: :string, nullable: true},
        free_text_document: %Schema{type: :object, additionalProperties: true, nullable: true},
        body: body_schema()
      },
      required: [:id, :title, :type, :sections],
      additionalProperties: false
    }
  end

  @rich_document %Schema{
    type: :object,
    nullable: true,
    additionalProperties: true,
    description:
      "The editor's rich text (TipTap/ProseMirror JSON): marks such as bold, italic, " <>
        "underline, strike, textStyle colour and highlight; nodes such as headings, lists and quotes"
  }

  @doc """
  ADR-224: what a workout says, as a union keyed by `kind`, carrying only the
  data of the way it was written.
  """
  def body_schema do
    %Schema{
      title: "WorkoutBody",
      oneOf: [free_text_body_schema(), text_sections_body_schema(), structured_body_schema()],
      discriminator: %OpenApiSpex.Discriminator{propertyName: "kind"}
    }
  end

  defp free_text_body_schema do
    %Schema{
      title: "FreeTextWorkoutBody",
      description: "One text written with the WOD assistant",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ["free_text"]},
        text: @nullable_string,
        document: @rich_document,
        timer: %Schema{type: :object, nullable: true, additionalProperties: true},
        structured: %Schema{
          type: :boolean,
          description: "The assistant also derived exercises (see `sections`)"
        }
      },
      required: [:kind, :text, :document, :timer, :structured],
      additionalProperties: false
    }
  end

  defp text_sections_body_schema do
    %Schema{
      title: "TextSectionsWorkoutBody",
      description: "ADR-180: text sections written without the assistant, a timer each",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ["text_sections"]},
        sections: %Schema{
          type: :array,
          items: %Schema{
            title: "TextSection",
            type: :object,
            properties: %{
              id: @nullable_uuid,
              title: %Schema{type: :string, nullable: true, description: "Null when untitled"},
              text: %Schema{type: :string},
              document: @rich_document,
              timer: section_timer_preset_schema(),
              scoring: %Schema{
                type: :array,
                items: %Schema{type: :object, additionalProperties: true},
                description:
                  "What the section counts (SectionScoring metrics), empty when not scored"
              }
            },
            required: [:id, :title, :text, :document, :timer, :scoring],
            additionalProperties: false
          }
        }
      },
      required: [:kind, :sections],
      additionalProperties: false
    }
  end

  defp structured_body_schema do
    %Schema{
      title: "StructuredWorkoutBody",
      description: "Exercises with every parameter (structured editor, Quick Text)",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: ["structured"]},
        sections: %Schema{
          type: :array,
          items: %Schema{
            title: "StructuredSection",
            type: :object,
            properties: %{
              id: @nullable_uuid,
              name: %Schema{type: :string},
              subtitle: @nullable_string,
              timer: %Schema{type: :object, nullable: true, additionalProperties: true},
              scoreable: %Schema{type: :boolean},
              exercises: %Schema{
                type: :array,
                items: %Schema{type: :object, additionalProperties: true},
                description: "Every exercise with its full prescription (the WorkoutItem shape)"
              }
            },
            required: [:id, :name, :timer, :scoreable, :exercises],
            additionalProperties: false
          }
        }
      },
      required: [:kind, :sections],
      additionalProperties: false
    }
  end

  @doc "ADR-224: the body in workout lists: excerpts and counts, no documents."
  def body_summary_schema do
    %Schema{
      title: "WorkoutBodySummary",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: Palee.Workouts.Domain.WorkoutBody.kinds()},
        excerpt: @nullable_string,
        timer: %Schema{type: :object, nullable: true, additionalProperties: true},
        structured: %Schema{type: :boolean},
        sections: %Schema{
          type: :array,
          items: %Schema{type: :object, additionalProperties: true}
        }
      },
      required: [:kind],
      additionalProperties: false
    }
  end

  def response_schema do
    %Schema{
      type: :object,
      properties: %{workout: workout_schema()},
      required: [:workout],
      additionalProperties: false
    }
  end

  # ADR-140 §4: Οδηγίες (instructions, scaling, safety, equipment), a cue
  # beside an exercise, and the staff-only coach-brief.
  defp content_entry_schema do
    %Schema{
      type: :object,
      properties: %{
        type: %Schema{type: :string, enum: WorkoutContent.types()},
        body: %Schema{type: :string, maxLength: 20_000},
        document: %Schema{type: :object, nullable: true, additionalProperties: true}
      },
      required: [:type, :body],
      additionalProperties: false
    }
  end

  def materialized_response_schema do
    %Schema{
      type: :object,
      properties: %{
        workout: workout_schema(),
        scales: %Schema{type: :array, items: workout_schema()}
      },
      required: [:workout, :scales],
      additionalProperties: false
    }
  end

  defp scale_level_schema do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{
        id: @nullable_uuid,
        slug: %Schema{type: :string},
        label: %Schema{type: :string},
        sort_order: %Schema{type: :integer},
        is_active: %Schema{type: :boolean}
      },
      additionalProperties: false
    }
  end
end
