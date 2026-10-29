defmodule PaleeWeb.Schemas.PlanWorkload do
  @moduledoc """
  ADR-270: OpenAPI schema of what an athlete did in a structured plan
  workout (`Palee.Workouts.Domain.PlanWorkload`): sets, reps, volume
  (kg × reps), calories, distance and work time per exercise and section,
  the section's time domain, and whether any number is an estimate (a
  range's midpoint, a % load without a known 1RM, rounds not known).
  """

  alias OpenApiSpex.Schema

  @number %Schema{type: :number}
  @nullable_string %Schema{type: :string, nullable: true}
  @nullable_integer %Schema{type: :integer, nullable: true}

  @amounts %{
    sets: @number,
    logged_sets: %Schema{type: :integer},
    reps: @number,
    volume_kg: @number,
    calories: @number,
    distance_m: @number,
    work_secs: @number,
    estimated: %Schema{type: :boolean}
  }

  defp top_set_schema do
    %Schema{
      type: :object,
      nullable: true,
      properties: %{load_kg: @number, reps: %Schema{type: :number, nullable: true}}
    }
  end

  defp exercise_schema(extra) do
    %Schema{
      type: :object,
      properties:
        @amounts
        |> Map.merge(%{
          name: @nullable_string,
          exercise_ref: @nullable_string,
          top_set: top_set_schema()
        })
        |> Map.merge(extra)
    }
  end

  defp section_schema do
    %Schema{
      type: :object,
      properties: %{
        section_id: %Schema{type: :string},
        name: @nullable_string,
        flow: %Schema{type: :string},
        score: @nullable_string,
        preset: @nullable_string,
        open_ended: %Schema{type: :boolean},
        source: %Schema{type: :string, enum: ["actuals", "prescription"]},
        time_domain: %Schema{
          type: :object,
          properties: %{
            planned_secs: @nullable_integer,
            cap_secs: @nullable_integer,
            open_ended: %Schema{type: :boolean}
          }
        },
        exercises: %Schema{
          type: :array,
          items:
            exercise_schema(%{
              row_id: %Schema{type: :string},
              block_index: %Schema{type: :integer},
              interrupt: %Schema{type: :boolean},
              group_id: @nullable_string,
              per_side: %Schema{type: :boolean}
            })
        },
        totals: %Schema{type: :object, properties: @amounts}
      }
    }
  end

  @doc "The workload of a plan workout's execution; null for other workouts."
  def schema do
    %Schema{
      title: "PlanWorkload",
      type: :object,
      nullable: true,
      properties: %{
        totals: %Schema{type: :object, properties: @amounts},
        exercises: %Schema{type: :array, items: exercise_schema(%{})},
        sections: %Schema{type: :array, items: section_schema()}
      }
    }
  end
end
