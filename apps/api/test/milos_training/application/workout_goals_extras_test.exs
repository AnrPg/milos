defmodule MilosTraining.Application.WorkoutGoalsExtrasTest do
  @moduledoc """
  ADR-163 extras: the gym's default for the members toggle, and goals that
  class variants and copies inherit from the workout they were copied from.
  """
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{
    DuplicateWorkout,
    GetAdminSettings,
    GetGoalFeedback,
    GetMemberWorkoutGoals,
    GetWorkoutGoals,
    SaveWorkoutGoals,
    UpdateAdminSettings
  }

  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Organizations, TestFixtures, Workouts}
  alias MilosTraining.Workouts.WorkoutGoal

  setup do
    {org, owner, staff} = organization_fixture()
    {member, member_context} = member_context(org)

    workout =
      TestFixtures.workout_fixture(owner, %{
        tenant_context: staff,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [%{name: "Back Squat", order: 1, sets: 5, prescription_value: 5}]
          }
        ]
      })

    %{org: org, owner: owner, staff: staff, member: member, member_context: member_context}
    |> Map.put(:workout, workout)
  end

  defp goals_params(extra \\ %{}) do
    Map.merge(
      %{
        "muscles" => [
          %{"id" => "quadriceps", "role" => "primary"},
          %{"id" => "gluteus-maximus", "role" => "secondary"}
        ],
        "qualities" => ["strength"],
        "stimulus" => "Heavy legs"
      },
      extra
    )
  end

  defp set_default(ctx, value) do
    {:ok, _settings} =
      UpdateAdminSettings.call(ctx.staff, %{workouts: %{wod_goals_visible_by_default: value}})
  end

  defp variant_of(ctx, workout_id) do
    {:ok, draft} = DuplicateWorkout.call(ctx.staff, workout_id, copy_goals: false)
    {:ok, variant} = Workouts.publish_workout(ctx.staff, draft.id, %{expected_source_revision: 0})
    variant
  end

  describe "gym default visibility" do
    test "is off by default and exposed through the admin settings", ctx do
      assert {:ok, %{workouts: %{wod_goals_visible_by_default: false}}} =
               GetAdminSettings.call(ctx.staff)

      assert {:ok, %{goals: %{visible_to_members: false}}} =
               GetWorkoutGoals.call(ctx.staff, ctx.workout.id)
    end

    test "sets the toggle of unsaved goals and the first save without it", ctx do
      assert {:ok, %{workouts: %{wod_goals_visible_by_default: true}}} = set_default(ctx, true)

      assert {:ok, %{workouts: %{wod_goals_visible_by_default: true}}} =
               GetAdminSettings.call(ctx.staff)

      assert {:ok, %{goals: %{saved: false, visible_to_members: true}}} =
               GetWorkoutGoals.call(ctx.staff, ctx.workout.id)

      assert {:ok, %{goals: %{saved: true, visible_to_members: true}}} =
               SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, goals_params())

      # Saved goals keep their own value whatever the default becomes.
      set_default(ctx, false)

      assert {:ok, %{goals: %{visible_to_members: true}}} =
               SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, goals_params())

      # An explicit toggle always wins.
      assert {:ok, %{goals: %{visible_to_members: false}}} =
               SaveWorkoutGoals.call(
                 ctx.staff,
                 ctx.workout.id,
                 goals_params(%{"visible_to_members" => false})
               )
    end

    test "other settings saves leave it alone; a bad value is rejected", ctx do
      set_default(ctx, true)

      assert {:ok, %{workouts: %{wod_goals_visible_by_default: true}}} =
               UpdateAdminSettings.call(ctx.staff, %{scheduling: %{default_capacity: 12}})

      assert {:error, :bad_request} =
               Organizations.update_workout_settings(ctx.staff, %{
                 "wod_goals_visible_by_default" => "yes"
               })
    end

    test "only settings managers change it", ctx do
      {_coach, coach_context} = member_context(ctx.org, :coach)

      assert {:error, :forbidden} =
               Organizations.update_workout_settings(coach_context, %{
                 "wod_goals_visible_by_default" => true
               })

      assert %{wod_goals_visible_by_default: false} =
               Organizations.get_workout_settings(coach_context)
    end
  end

  describe "inherited goals" do
    setup ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => true})
        )

      %{variant: variant_of(ctx, ctx.workout.id)}
    end

    test "a variant without goals of its own uses the base workout's", ctx do
      assert {:ok, %{goals: goals}} = GetWorkoutGoals.call(ctx.staff, ctx.variant.id)
      assert goals.saved == false
      assert goals.inherited_from == ctx.workout.id
      assert goals.workout_id == ctx.variant.id
      assert goals.stimulus == "Heavy legs"
      assert goals.visible_to_members

      assert {:ok, %{goals: member_goals}} =
               GetMemberWorkoutGoals.call(ctx.member_context, ctx.variant.id)

      assert member_goals.workout_id == ctx.variant.id
      assert member_goals.stimulus == "Heavy legs"

      # The base's own read is not inherited.
      assert {:ok, %{goals: %{saved: true, inherited_from: nil}}} =
               GetWorkoutGoals.call(ctx.staff, ctx.workout.id)

      assert Repo.aggregate(WorkoutGoal, :count) == 1
    end

    test "follows later edits of the base, visibility included", ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"stimulus" => "Fast feet", "visible_to_members" => false})
        )

      assert {:ok, %{goals: %{stimulus: "Fast feet", visible_to_members: false}}} =
               GetWorkoutGoals.call(ctx.staff, ctx.variant.id)

      assert {:ok, %{goals: nil}} = GetMemberWorkoutGoals.call(ctx.member_context, ctx.variant.id)
    end

    test "a save on the variant gives it goals of its own", ctx do
      assert {:ok, %{goals: own}} =
               SaveWorkoutGoals.call(
                 ctx.staff,
                 ctx.variant.id,
                 goals_params(%{"stimulus" => "Scaled: steady"})
               )

      # Saved without the toggle: it keeps the inherited value.
      assert own.saved and own.inherited_from == nil and own.visible_to_members
      assert own.stimulus == "Scaled: steady"

      assert {:ok, %{goals: %{stimulus: "Heavy legs"}}} =
               GetWorkoutGoals.call(ctx.staff, ctx.workout.id)

      assert {:ok, %{goals: %{stimulus: "Scaled: steady"}}} =
               GetMemberWorkoutGoals.call(ctx.member_context, ctx.variant.id)
    end

    test "inherits through a chain of copies", ctx do
      grandchild = variant_of(ctx, ctx.variant.id)

      assert {:ok, %{goals: %{inherited_from: inherited_from}}} =
               GetWorkoutGoals.call(ctx.staff, grandchild.id)

      assert inherited_from == ctx.workout.id
    end

    test "the feedback checklist shows the inherited goals", ctx do
      execution =
        Repo.insert!(%WorkoutExecution{
          user_id: ctx.member.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.variant.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        })

      assert {:ok, %{goals: goals}} =
               GetGoalFeedback.call(ctx.member_context, "execution", execution.id)

      assert goals.workout_id == ctx.variant.id
      assert %{id: "quadriceps", role: "primary"} in goals.muscles
    end

    test "a plain duplicate still copies the goals", ctx do
      assert {:ok, copy} = DuplicateWorkout.call(ctx.staff, ctx.workout.id, [])

      assert {:ok, %{goals: %{saved: true, inherited_from: nil}}} =
               GetWorkoutGoals.call(ctx.staff, copy.id)
    end
  end
end
