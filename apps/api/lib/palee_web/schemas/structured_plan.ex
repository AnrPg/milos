defmodule PaleeWeb.Schemas.StructuredPlan do
  @moduledoc """
  ADR-270: OpenAPI schemas of a structured WOD plan section (the web
  contract `PlanSection` in `apps/web/src/lib/structured-plan/types.ts`),
  its canonical read model (`StructuredPlan.Prescription`) and the plan
  actuals an execution records.
  """

  alias OpenApiSpex.Schema
  alias Palee.Workouts.Domain.StructuredPlan.Catalog

  @string %Schema{type: :string}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_integer %Schema{type: :integer, nullable: true}
  @nullable_number %Schema{type: :number, nullable: true}
  @measures ~w(pace tempo rpe rir zone height dist hold)a

  @param_keys ~w(sets rest rounds cap dur every times work off intEvery hrTarget)a

  defp strings(keys), do: Map.new(keys, &{&1, @string})

  @doc "One row's values in one set / round: `d` reps, `l` load, measures."
  def cell_schema do
    %Schema{
      title: "PlanCell",
      type: :object,
      nullable: true,
      properties: strings([:d, :l | @measures]),
      additionalProperties: false
    }
  end

  def row_schema do
    %Schema{
      title: "PlanRow",
      type: :object,
      properties: %{
        id: %Schema{type: :string, maxLength: 200},
        kind: %Schema{type: :string, enum: ["ex", "rest"]},
        name: %Schema{type: :string, maxLength: 200},
        exerciseRef: %Schema{type: :string, maxLength: 200, nullable: true},
        dose: @string,
        load: @string,
        x: %Schema{type: :object, properties: strings(@measures), additionalProperties: false},
        extra: %Schema{type: :array, items: %Schema{type: :string, enum: Catalog.measure_keys()}},
        cells: %Schema{type: :array, maxItems: 30, items: cell_schema()},
        perRound: %Schema{type: :boolean},
        group: %Schema{type: :string, maxLength: 200, nullable: true},
        note: %Schema{type: :string, maxLength: 2000}
      },
      required: [:cells, :dose, :id, :kind, :load, :name],
      additionalProperties: false
    }
  end

  def structure_schema do
    %Schema{
      title: "PlanStructure",
      type: :object,
      properties: %{
        kind: %Schema{type: :string, enum: Catalog.struct_keys()},
        clusters: @string,
        intra: @string,
        drops: @string,
        dropby: @string,
        minis: @string
      },
      required: [:kind],
      additionalProperties: false
    }
  end

  @doc "ADR-270: one section of a structured WOD plan, values as typed by the coach."
  def plan_section_schema do
    %Schema{
      title: "PlanSection",
      type: :object,
      nullable: true,
      description:
        "ADR-270: a structured WOD plan section (camelCase keys, values as typed by the coach); " <>
          "validated by Palee.Workouts.Domain.StructuredPlan",
      properties: %{
        v: %Schema{type: :integer, enum: [1]},
        flow: %Schema{type: :string, enum: Catalog.flow_keys()},
        preset: @nullable_string,
        params: %Schema{
          title: "PlanParams",
          type: :object,
          properties: strings(@param_keys),
          additionalProperties: false
        },
        mods: %Schema{
          title: "PlanMods",
          type: :object,
          properties: %{interrupt: %Schema{type: :boolean}, hr: %Schema{type: :boolean}},
          additionalProperties: false
        },
        blocks: %Schema{
          type: :array,
          maxItems: 12,
          items: %Schema{type: :array, maxItems: 60, items: row_schema()}
        },
        interrupt: %Schema{type: :array, maxItems: 60, items: row_schema()},
        structs: %Schema{type: :object, additionalProperties: structure_schema()},
        score: %Schema{type: :string, enum: Catalog.score_keys()},
        note: %Schema{type: :string, maxLength: 2000},
        levelNotes: %Schema{
          type: :object,
          additionalProperties: %Schema{type: :string, maxLength: 2000}
        }
      },
      required: [:blocks, :flow, :params, :score, :v],
      additionalProperties: false
    }
  end

  defp min_max(type),
    do: %Schema{
      type: :object,
      nullable: true,
      properties: %{min: %Schema{type: type}, max: %Schema{type: type}},
      required: [:max, :min]
    }

  def clock_schema do
    %Schema{
      title: "PlanClock",
      type: :object,
      description: "How a plan section runs, unit-normalised (seconds, counts)",
      properties: %{
        flow: %Schema{type: :string, enum: Catalog.flow_keys()},
        preset: @nullable_string,
        score: @nullable_string,
        sets: min_max(:integer),
        rest_secs: min_max(:integer),
        rounds: @nullable_integer,
        cap_secs: @nullable_integer,
        windows_secs: %Schema{type: :array, nullable: true, items: %Schema{type: :integer}},
        every_secs: @nullable_integer,
        times: @nullable_integer,
        work_secs: @nullable_integer,
        off_secs: @nullable_integer,
        dur_secs: @nullable_integer,
        interrupt_every_secs: @nullable_integer,
        hr_target_bpm: @nullable_integer,
        blocks: %Schema{type: :integer},
        open_ended: %Schema{
          type: :boolean,
          description: "AMRAP, or EMOM without times: no last round"
        },
        total_rounds: %Schema{type: :integer, nullable: true, description: "Null when open-ended"}
      },
      required: [
        :blocks,
        :cap_secs,
        :dur_secs,
        :every_secs,
        :flow,
        :hr_target_bpm,
        :interrupt_every_secs,
        :off_secs,
        :open_ended,
        :preset,
        :rest_secs,
        :rounds,
        :score,
        :sets,
        :times,
        :total_rounds,
        :windows_secs,
        :work_secs
      ],
      additionalProperties: false
    }
  end

  def reps_schema do
    %Schema{
      title: "PlanReps",
      type: :object,
      nullable: true,
      properties: %{
        min: @nullable_number,
        max: @nullable_number,
        unit: %Schema{type: :string, enum: ["reps", "secs", "meters", "kcal"]},
        max_effort: %Schema{type: :boolean},
        within_secs: @nullable_integer,
        sets: min_max(:integer),
        text: @nullable_string
      },
      required: [:max, :max_effort, :min, :sets, :text, :unit, :within_secs],
      additionalProperties: false
    }
  end

  def load_schema do
    %Schema{
      title: "PlanLoad",
      type: :object,
      nullable: true,
      properties: %{
        kind: %Schema{type: :string, enum: ["kg", "pct_1rm", "bodyweight", "qualitative"]},
        value: %Schema{type: :number, nullable: true, description: "Decimal (22.5)"},
        value_max: %Schema{type: :number, nullable: true},
        text: @nullable_string
      },
      required: [:kind, :text, :value, :value_max],
      additionalProperties: false
    }
  end

  def measures_schema do
    mark = %Schema{oneOf: [%Schema{type: :integer}, %Schema{type: :string, enum: ["X"]}]}

    %Schema{
      title: "PlanMeasures",
      type: :object,
      properties: %{
        pace_secs_per_500m: @nullable_number,
        tempo: %Schema{
          type: :object,
          nullable: true,
          properties: %{down: mark, bottom: mark, up: mark, top: mark},
          required: [:bottom, :down, :top, :up]
        },
        rpe: @nullable_number,
        rir: @nullable_number,
        hr_zone: @nullable_integer,
        height_cm: @nullable_number,
        distance_m: @nullable_number,
        hold_secs: @nullable_number
      },
      required: [
        :distance_m,
        :height_cm,
        :hold_secs,
        :hr_zone,
        :pace_secs_per_500m,
        :rir,
        :rpe,
        :tempo
      ],
      additionalProperties: false
    }
  end

  def prescription_schema do
    set = %Schema{
      title: "PlanSetPrescription",
      type: :object,
      properties: %{
        index: %Schema{type: :integer, minimum: 1},
        rounds: %Schema{
          type: :array,
          items: %Schema{type: :integer},
          description: "1-based rounds it applies to (empty: every interruption)"
        },
        reps: reps_schema(),
        load: load_schema(),
        rest_secs: @nullable_integer,
        measures: measures_schema()
      },
      required: [:index, :load, :measures, :reps, :rest_secs, :rounds],
      additionalProperties: false
    }

    row = %Schema{
      title: "PlanRowPrescription",
      type: :object,
      properties: %{
        row_id: @string,
        kind: %Schema{type: :string, enum: ["exercise", "rest"]},
        name: @nullable_string,
        exercise_ref: @nullable_string,
        note: @nullable_string,
        block_index: %Schema{type: :integer, minimum: -1, description: "-1: an interruption row"},
        interrupt: %Schema{type: :boolean},
        group_id: @nullable_string,
        structure: %Schema{
          title: "PlanStructurePrescription",
          type: :object,
          properties: %{
            kind: %Schema{type: :string, enum: Catalog.struct_keys()},
            clusters: @nullable_integer,
            intra_secs: @nullable_integer,
            drops: @nullable_integer,
            drop_by: @nullable_string,
            minis: @nullable_integer
          },
          required: [:clusters, :drop_by, :drops, :intra_secs, :kind, :minis],
          additionalProperties: false
        },
        per_side: %Schema{type: :boolean},
        sets: %Schema{type: :array, items: set},
        then: %Schema{
          title: "PlanThenRule",
          type: :object,
          nullable: true,
          description: "Open-ended flows: what follows the written rounds",
          properties: %{
            rule: %Schema{type: :string, enum: ["repeat", "step"]},
            reps_step: @nullable_number,
            load_step: @nullable_number
          },
          required: [:load_step, :reps_step, :rule],
          additionalProperties: false
        }
      },
      required: [
        :block_index,
        :exercise_ref,
        :group_id,
        :interrupt,
        :kind,
        :name,
        :note,
        :per_side,
        :row_id,
        :sets,
        :structure,
        :then
      ],
      additionalProperties: false
    }

    %Schema{
      title: "PlanPrescription",
      type: :object,
      nullable: true,
      description:
        "ADR-270: the plan section's canonical read model (StructuredPlan.Prescription); " <>
          "null outside structured_plan workouts",
      properties: %{clock: clock_schema(), rows: %Schema{type: :array, items: row}},
      required: [:clock, :rows],
      additionalProperties: false
    }
  end

  @actual_numbers ~w(prescribed_reps prescribed_load_kg prescribed_load_pct one_rep_max_kg actual_reps actual_load_kg)a

  defp actual_properties do
    numbers =
      Map.new(@actual_numbers, &{&1, %Schema{type: :number, minimum: 0, nullable: true}})

    Map.merge(numbers, %{
      section_id: %Schema{type: :string, format: :uuid},
      row_id: %Schema{type: :string, maxLength: 200},
      exercise_name: %Schema{type: :string, maxLength: 200},
      exercise_ref: %Schema{type: :string, maxLength: 200, nullable: true},
      block_index: %Schema{
        type: :integer,
        minimum: -1,
        maximum: 11,
        description: "The row's block; -1 for an interruption row"
      },
      round_index: %Schema{
        type: :integer,
        minimum: 1,
        description: "1-based set / round / slot / interval; for an interruption, which one"
      },
      part_index: %Schema{type: :integer, minimum: 0, description: "Cluster / drop part"},
      phase_index: %Schema{type: :integer, minimum: 0, description: "AMRAP window, EMOM slot"},
      interrupt: %Schema{type: :boolean},
      prescribed_reps_text: %Schema{type: :string, maxLength: 200},
      prescribed_load_text: %Schema{type: :string, maxLength: 200},
      logged: %Schema{
        type: :boolean,
        description: "The athlete typed a value (otherwise actual = prescribed)"
      }
    })
  end

  @doc "ADR-270: one set / round of a plan row as done, sent with the completion."
  def plan_actual_schema do
    %Schema{
      title: "PlanSetActual",
      type: :object,
      description:
        "ADR-270: one set / round of a structured plan row, prescribed next to actual " <>
          "(checked by Palee.Execution.Domain.PlanActuals)",
      properties: actual_properties(),
      required: [:block_index, :round_index, :row_id, :section_id]
    }
  end

  @doc "ADR-270: a stored plan actual, as execution reads show it."
  def plan_set_schema do
    properties =
      Map.merge(actual_properties(), %{
        id: %Schema{type: :string, format: :uuid},
        inserted_at: %Schema{type: :string, format: :"date-time"}
      })

    %Schema{
      title: "ExecutionPlanSet",
      type: :object,
      properties: properties,
      required: properties |> Map.keys() |> Enum.sort(),
      additionalProperties: false
    }
  end

  @doc "An execution read with its plan actuals typed; the rest stays open."
  def execution_response_schema do
    %Schema{
      title: "ExecutionResponse",
      type: :object,
      properties: %{
        execution: %Schema{
          type: :object,
          properties: %{
            plan_sets: %Schema{
              type: :array,
              items: plan_set_schema(),
              description:
                "ADR-270: plan actuals of a completed structured_plan execution, in run order"
            }
          },
          additionalProperties: true
        }
      },
      required: [:execution]
    }
  end
end
