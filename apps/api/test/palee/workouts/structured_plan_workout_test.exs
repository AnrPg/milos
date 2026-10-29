defmodule Palee.Workouts.StructuredPlanWorkoutStoreTest do
  @moduledoc "ADR-270: a structured plan workout is saved, read, published and copied with its plans."
  use Palee.DataCase, async: false

  import Palee.StructuredPlanFixtures

  alias Palee.{Identity, Organizations, Repo}
  alias Palee.Infrastructure.Workouts.EctoWorkoutStore
  alias Palee.Workouts
  alias Palee.Workouts.{WorkoutExercise, WorkoutSection}

  defp params(sections) do
    %{
      title: "Structured Saturday",
      type: "crossfit",
      authoring_mode: "structured_plan",
      sections: sections
    }
  end

  defp plan_sections do
    [
      %{name: "Strength", order: 1, plan: Enum.at(program(), 0)},
      # The client's exercises are ignored: the plan is the source of truth.
      %{name: "Accessory", order: 2, plan: Enum.at(program(), 1), exercises: [%{name: "Stale"}]},
      %{name: "Engine", order: 3, plan: Enum.at(program(), 8)}
    ]
  end

  test "create keeps every section's plan and materialises its exercises" do
    admin = create_admin!("plan_author")

    assert {:ok, workout} = Workouts.create_workout(admin, params(plan_sections()))
    assert workout.authoring_mode == "structured_plan"

    [strength, accessory, engine] = workout.sections
    assert strength.plan["flow"] == "sets"

    assert [%{name: "Back Squat", sets: 4, prescription_value: 12, tempo: "31X1"}] =
             strength.exercises

    assert %{load_value: 60, load_mode: "pct_1rm"} = hd(strength.exercises)

    assert Enum.map(accessory.exercises, & &1.name) ==
             ["Knee Extension", "Standing Calf Raise", "Cyclist Squat"]

    assert accessory.exercises |> Enum.map(& &1.superset_group_id) |> Enum.uniq() |> length() == 1
    assert Enum.map(engine.exercises, & &1.name) == ["Row", "Burpee", "Run", "Wall Ball"]

    # The plan's score is the section's, for leaderboards and PR detection.
    assert %{scoreable: true, score_config: %{"type" => "time", "plan_score" => "time"}} = engine

    assert %{kind: "plan", sections: [%{name: "Strength", plan: %{"flow" => "sets"}} | _]} =
             workout.body

    # Read back from the database.
    fetched = EctoWorkoutStore.get_workout(workout.id)
    assert Enum.map(fetched.sections, & &1.plan["flow"]) == ["sets", "sets", "for_time"]
    assert Repo.aggregate(WorkoutExercise, :count) == 8
  end

  test "a plan that does not read is refused with its section and path" do
    admin = create_admin!("plan_refused")

    bad =
      put_in(Enum.at(program(), 0), ["blocks", Access.at(0), Access.at(0), "cells"], [
        %{"l" => "60"}
      ])

    assert {:error,
            {:invalid_plan_sections,
             [%{section: 1, path: "blocks.0.0.cells.0.l", code: "missing_unit"}]}} =
             Workouts.create_workout(admin, params([%{name: "A", order: 1, plan: bad}]))

    assert {:error, {:invalid_plan_sections, [%{section: 1, code: "plan_required"}]}} =
             Workouts.create_workout(admin, params([%{name: "A", order: 1, exercises: []}]))
  end

  test "the section changeset validates a plan" do
    valid = WorkoutSection.persist_changeset(%{name: "A", order: 1, plan: Enum.at(program(), 2)})
    assert valid.valid?

    invalid =
      WorkoutSection.persist_changeset(%{
        name: "A",
        order: 1,
        plan: Map.put(Enum.at(program(), 2), "flow", "crossfit")
      })

    assert %{plan: ["is invalid at flow (unknown_flow)"]} = errors_on(invalid)
  end

  test "draft, publish, update and copy carry the plan along" do
    admin = create_admin!("plan_copier")
    {:ok, draft} = Workouts.create_draft(admin)

    {:ok, saved} =
      Workouts.update_draft(draft.id, %{
        draft_data: params(plan_sections()),
        expected_source_revision: 0
      })

    assert {:ok, published} =
             Workouts.publish_workout(draft.id, %{
               expected_source_revision: saved.dsl_source_revision
             })

    assert Enum.map(published.sections, & &1.plan["flow"]) == ["sets", "sets", "for_time"]
    assert length(hd(published.sections).exercises) == 1

    # Reopened and edited: the new plan is saved and the exercises follow it.
    {:ok, _reopened} = Workouts.reopen_workout(published.id)
    edited = [%{name: "Only", order: 1, plan: Enum.at(program(), 9)}]

    assert {:ok, updated} =
             Workouts.publish_workout(
               published.id,
               Map.put(params(edited), :expected_source_revision, published.dsl_source_revision)
             )

    assert [%{plan: %{"flow" => "amrap"}, exercises: exercises}] = updated.sections
    assert Enum.map(exercises, & &1.name) == ["Echo Bike", "Wall Ball", "Clean & Jerk"]

    # A copy (copy WOD, class variants, member versions) publishes with the same plans.
    assert {:ok, %{id: copy_id}} = Workouts.duplicate_workout(updated.id, "(copy)", %{})
    assert {:ok, copy} = Workouts.publish_workout(copy_id, %{expected_source_revision: 0})
    assert copy.authoring_mode == "structured_plan"
    assert [%{plan: plan, exercises: [_, _, _]}] = copy.sections
    assert plan == hd(updated.sections).plan
  end

  test "a scale level keeps the plan, its prescription and its plan timer" do
    admin = create_admin!("plan_scaler")
    {:ok, workout} = Workouts.create_workout(admin, params(plan_sections()))

    scaled = Workouts.materialize_for_scale(workout, "scaled")
    assert Enum.map(scaled.sections, & &1.plan) == Enum.map(workout.sections, & &1.plan)
    assert Enum.all?(scaled.sections, &match?(%{clock: %{}}, &1.prescription))

    assert ["plan:" <> _, "plan:" <> _, "plan:" <> _] =
             scaled |> Palee.Execution.build_timer_sequence() |> Enum.map(& &1.segment_key)
  end

  defp create_admin!(nickname) do
    {:ok, user} =
      Identity.register(%{
        nickname: nickname,
        password: "S3cur3P@ss!42",
        role: :member,
        email: "u#{System.unique_integer([:positive])}@placeholder.invalid"
      })

    {:ok, admin} = Identity.update_role(user, :admin)
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])
    Repo.query!("SELECT set_config($1, $2, false)", ["app.user_id", admin.id])
    admin
  end
end
