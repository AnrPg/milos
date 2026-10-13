defmodule MilosTraining.Workouts.Domain.TenantDataPolicy do
  @moduledoc """
  Workouts tenant data retention and purge policy (ADR-117).

  Declares the tables this context owns, in delete (dependency) order, and
  how they are treated when a tenant is purged.
  """

  alias MilosTraining.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "workouts",
            purge_order: 110,
            disposition: :purge,
            basis:
              "Workout programming is tenant content with no retention obligation; purged last because classes and executions reference it.",
            tables: [
              %{table: "assigned_workout_athletes"},
              %{table: "assigned_workouts"},
              %{table: "exercise_variations"},
              %{table: "workout_exercises"},
              %{table: "workout_sections"},
              %{table: "master_workouts"},
              %{table: "workout_folders"},
              # ADR-128: after exercise_variations, which reference it.
              %{table: "scale_levels"}
            ]
          })

  def policy, do: @policy
end
