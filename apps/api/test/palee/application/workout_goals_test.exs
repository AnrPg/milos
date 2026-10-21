defmodule Palee.Application.WorkoutGoalsTest do
  @moduledoc "ADR-163: WOD goal and «τι ένιωσες» use cases."
  use Palee.DataCase, async: false

  import Ecto.Query
  import Palee.AnalyticsHelpers

  alias Palee.Application.{
    DuplicateWorkout,
    GetGoalFeedback,
    GetMemberWorkoutGoals,
    GetWorkoutGoals,
    LogTrainingEntry,
    SaveGoalFeedback,
    SaveWorkoutGoals,
    VoidTrainingLogEntry
  }

  alias Palee.Execution.WorkoutExecution
  alias Palee.{Anatomy, TestFixtures, Workouts}
  alias Palee.Workouts.{MasterWorkout, WorkoutGoal}

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
            exercises: [
              %{name: "Back Squat", order: 1, sets: 5, prescription_value: 5},
              %{name: "Box Jumps", order: 2, sets: 3, prescription_value: 10},
              %{name: "Partner relay", order: 3, sets: 1, prescription_value: 1}
            ]
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
        "qualities" => ["strength", "power"],
        "stimulus" => "  Heavy legs, fast feet  "
      },
      extra
    )
  end

  describe "staff goals" do
    test "without saved goals, returns the live suggestion and its counts", ctx do
      assert {:ok, %{goals: goals, suggestion: suggestion}} =
               GetWorkoutGoals.call(ctx.staff, ctx.workout.id)

      assert suggestion.matched_exercises == 2
      assert suggestion.unmatched_exercises == 1
      assert suggestion.taxonomy_version == Anatomy.taxonomy_version()
      assert %{id: "quadriceps", role: "primary"} in suggestion.muscles
      assert "strength" in suggestion.qualities

      assert goals.saved == false
      assert goals.source == "suggested"
      assert goals.visible_to_members == false
      assert goals.muscles == suggestion.muscles
      assert goals.qualities == suggestion.qualities
    end

    test "saves normalised goals, stamps version and author, keeps visibility", ctx do
      assert {:ok, %{goals: goals}} =
               SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, goals_params())

      assert goals.saved
      assert goals.source == "edited"
      assert goals.stimulus == "Heavy legs, fast feet"
      assert goals.visible_to_members == false
      assert goals.updated_by_id == ctx.owner.id
      assert goals.taxonomy_version == Anatomy.taxonomy_version()
      assert goals.qualities == ["strength", "power"]

      assert {:ok, %{goals: visible}} =
               SaveWorkoutGoals.call(
                 ctx.staff,
                 ctx.workout.id,
                 goals_params(%{"visible_to_members" => true})
               )

      assert visible.visible_to_members

      # Left out: the saved toggle is kept.
      assert {:ok, %{goals: kept}} =
               SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, goals_params())

      assert kept.visible_to_members
      assert Repo.aggregate(WorkoutGoal, :count) == 1

      assert {:ok, %{goals: reread}} = GetWorkoutGoals.call(ctx.staff, ctx.workout.id)
      assert reread.saved and reread.stimulus == "Heavy legs, fast feet"
    end

    test "goals equal to the suggestion are marked suggested", ctx do
      {:ok, %{suggestion: suggestion}} = GetWorkoutGoals.call(ctx.staff, ctx.workout.id)

      params = %{
        "muscles" => Enum.map(suggestion.muscles, &%{"id" => &1.id, "role" => &1.role}),
        "qualities" => suggestion.qualities
      }

      assert {:ok, %{goals: %{source: "suggested"}}} =
               SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, params)
    end

    test "rejects muscles, roles and qualities outside the taxonomy", ctx do
      for params <- [
            goals_params(%{"muscles" => [%{"id" => "biceps-femoris", "role" => "primary"}]}),
            goals_params(%{"muscles" => [%{"id" => "quadriceps", "role" => "main"}]}),
            goals_params(%{"muscles" => [%{"id" => "legs", "role" => "primary"}]}),
            goals_params(%{"qualities" => ["grit"]}),
            goals_params(%{"visible_to_members" => "yes"})
          ] do
        assert {:error, {:invalid_goals, _details}} =
                 SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, params)
      end

      assert Repo.aggregate(WorkoutGoal, :count) == 0
    end

    test "another gym's workout is not found", ctx do
      {_other_org, _other_owner, other_staff} = organization_fixture()

      assert {:error, :not_found} = GetWorkoutGoals.call(other_staff, ctx.workout.id)

      assert {:error, :not_found} =
               SaveWorkoutGoals.call(other_staff, ctx.workout.id, goals_params())

      assert {:error, :not_found} = GetWorkoutGoals.call(ctx.staff, "not-a-uuid")
    end

    test "a free-text workout is suggested from its text", ctx do
      {:ok, draft} = Workouts.create_draft(ctx.staff, ctx.owner)

      {1, _} =
        MasterWorkout
        |> where([workout], workout.id == ^draft.id)
        |> Repo.update_all(
          set: [
            authoring_mode: "free_text",
            draft_data: %{
              "free_text_body" => "AMRAP 12\n10 Thrusters\n10 Pull-ups\nCool down chat"
            }
          ]
        )

      assert {:ok, %{suggestion: suggestion}} = GetWorkoutGoals.call(ctx.staff, draft.id)
      assert suggestion.matched_exercises == 2
      assert suggestion.unmatched_exercises == 1
      assert %{id: "latissimus-dorsi", role: "primary"} in suggestion.muscles
    end
  end

  describe "member goals" do
    test "hidden goals read as nil, visible ones are returned", ctx do
      assert {:ok, %{goals: nil}} = GetMemberWorkoutGoals.call(ctx.member_context, ctx.workout.id)

      {:ok, _} = SaveWorkoutGoals.call(ctx.staff, ctx.workout.id, goals_params())
      assert {:ok, %{goals: nil}} = GetMemberWorkoutGoals.call(ctx.member_context, ctx.workout.id)

      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => true})
        )

      assert {:ok, %{goals: goals}} =
               GetMemberWorkoutGoals.call(ctx.member_context, ctx.workout.id)

      assert goals.muscles == [
               %{id: "quadriceps", role: "primary"},
               %{id: "gluteus-maximus", role: "secondary"}
             ]

      refute Map.has_key?(goals, :visible_to_members)
    end

    test "another gym's member cannot read them", ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => true})
        )

      {other_org, _owner, _staff} = organization_fixture()
      {_other, other_context} = member_context(other_org)

      assert {:error, :not_found} = GetMemberWorkoutGoals.call(other_context, ctx.workout.id)
    end
  end

  describe "workout lifecycle" do
    test "duplicating copies the goals; deleting removes them", ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => true})
        )

      assert {:ok, copy} = DuplicateWorkout.call(ctx.staff, ctx.workout.id, [])

      assert {:ok, %{goals: copied}} = GetWorkoutGoals.call(ctx.staff, copy.id)
      assert copied.saved and copied.visible_to_members
      assert copied.stimulus == "Heavy legs, fast feet"
      assert copied.workout_id == copy.id

      assert :ok = Workouts.delete_workout(ctx.staff, ctx.workout.id)
      assert Repo.aggregate(WorkoutGoal, :count) == 1
    end
  end

  describe "goal feedback" do
    setup ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => true})
        )

      execution =
        Repo.insert!(%WorkoutExecution{
          user_id: ctx.member.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.workout.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        })

      %{execution: execution}
    end

    test "the owner reads the workout's goals and saves what they felt", ctx do
      id = ctx.execution.id

      assert {:ok, %{goals: goals, feedback: nil, voided: false, entry_id: ^id}} =
               GetGoalFeedback.call(ctx.member_context, "execution", id)

      assert goals.stimulus == "Heavy legs, fast feet"

      assert {:ok, %{feedback: feedback}} =
               SaveGoalFeedback.call(ctx.member_context, "execution", id, %{
                 "felt_muscles" => ["gluteus-maximus", "quadriceps", "quadriceps"],
                 "felt_qualities" => ["power"]
               })

      # Taxonomy order, without duplicates.
      assert feedback.felt_muscles == ["gluteus-maximus", "quadriceps"]
      assert feedback.felt_qualities == ["power"]

      assert {:ok, %{feedback: %{felt_qualities: ["strength"]}}} =
               SaveGoalFeedback.call(ctx.member_context, "execution", id, %{
                 "felt_muscles" => [],
                 "felt_qualities" => ["strength"]
               })

      assert {:ok, %{feedback: %{felt_muscles: [], felt_qualities: ["strength"]}}} =
               GetGoalFeedback.call(ctx.member_context, "execution", id)
    end

    test "rejects ids outside the taxonomy and unknown kinds", ctx do
      assert {:error, {:invalid_goals, _}} =
               SaveGoalFeedback.call(ctx.member_context, "execution", ctx.execution.id, %{
                 "felt_muscles" => ["spleen"]
               })

      assert {:error, :bad_request} =
               GetGoalFeedback.call(ctx.member_context, "pr", ctx.execution.id)
    end

    test "someone else's entry is not found", ctx do
      {_stranger, stranger_context} = member_context(ctx.org)

      assert {:error, :not_found} =
               GetGoalFeedback.call(stranger_context, "execution", ctx.execution.id)

      assert {:error, :not_found} =
               SaveGoalFeedback.call(stranger_context, "execution", ctx.execution.id, %{
                 "felt_muscles" => ["quadriceps"]
               })

      assert {:error, :not_found} =
               GetGoalFeedback.call(ctx.member_context, "execution", Ecto.UUID.generate())
    end

    test "hidden goals are not shown with the feedback", ctx do
      {:ok, _} =
        SaveWorkoutGoals.call(
          ctx.staff,
          ctx.workout.id,
          goals_params(%{"visible_to_members" => false})
        )

      assert {:ok, %{goals: nil}} =
               GetGoalFeedback.call(ctx.member_context, "execution", ctx.execution.id)
    end

    test "training-log entries take feedback; a voided entry keeps it but is frozen", ctx do
      {:ok, entry, :created} =
        LogTrainingEntry.call(ctx.member_context, ctx.member, %{
          "source_type" => "library_workout",
          "source_reference_id" => ctx.workout.id,
          "performed_at" =>
            DateTime.utc_now() |> DateTime.add(-3 * 86_400) |> DateTime.to_iso8601(),
          "idempotency_key" => "goals-" <> Ecto.UUID.generate()
        })

      assert {:ok, %{goals: %{}, feedback: %{felt_muscles: ["quadriceps"]}}} =
               SaveGoalFeedback.call(ctx.member_context, "training_log", entry.id, %{
                 "felt_muscles" => ["quadriceps"],
                 "felt_qualities" => []
               })

      {:ok, _voided} =
        VoidTrainingLogEntry.call(ctx.member_context, ctx.member, entry.id, %{
          "reason" => "duplicate"
        })

      assert {:ok, %{voided: true, feedback: %{felt_muscles: ["quadriceps"]}}} =
               GetGoalFeedback.call(ctx.member_context, "training_log", entry.id)

      assert {:error, :training_log_entry_voided} =
               SaveGoalFeedback.call(ctx.member_context, "training_log", entry.id, %{
                 "felt_muscles" => []
               })
    end
  end
end
