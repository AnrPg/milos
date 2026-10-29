defmodule Palee.Repo.Migrations.AddPlanToWorkoutSections do
  @moduledoc """
  ADR-270: a workout written in the structured WOD editor keeps one plan per
  section (`workout_sections.plan`, the web contract `PlanSection`, camelCase
  JSON, `v: 1`) and is marked `authoring_mode = 'structured_plan'`. Additive:
  existing sections keep a null plan, and the mode check only gains a value.
  """

  use Ecto.Migration

  def up do
    alter table(:workout_sections) do
      add :plan, :map
    end

    replace_mode_check(~w(structured quick_text free_text sectioned_text structured_plan))
  end

  def down do
    # A plan workout keeps its materialised exercises, so it still reads as a
    # structured one without the plan.
    execute("""
    UPDATE master_workouts SET authoring_mode = 'structured'
    WHERE authoring_mode = 'structured_plan'
    """)

    replace_mode_check(~w(structured quick_text free_text sectioned_text))

    alter table(:workout_sections) do
      remove :plan
    end
  end

  defp replace_mode_check(modes) do
    execute("ALTER TABLE master_workouts DROP CONSTRAINT master_workouts_authoring_mode_check")

    create constraint(:master_workouts, :master_workouts_authoring_mode_check,
             check: "authoring_mode IN (#{Enum.map_join(modes, ", ", &"'#{&1}'")})"
           )
  end
end
