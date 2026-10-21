defmodule MilosTrainingWeb.GoalFeedbackSummaryControllerTest do
  @moduledoc """
  ADR-163 extras over HTTP (requests run RLS-enforced): coach totals per
  workout and per scheduled class, the gym's goals default in the admin
  settings, and `inherited_from` on the staff goals read.
  """
  use MilosTrainingWeb.ConnCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{DuplicateWorkout, SaveWorkoutGoals}
  alias MilosTraining.Execution.{TrainingLogEntry, WorkoutExecution}
  alias MilosTraining.Journal.GoalFeedback
  alias MilosTraining.{Repo, TestFixtures, Workouts}

  setup do
    {org, owner, staff} = organization_fixture()
    {coach, _coach_context} = member_context(org, :coach)
    {front_desk, _context} = member_context(org, :front_desk)
    {member, _member_context} = member_context(org)
    workout = TestFixtures.workout_fixture(owner, %{tenant_context: staff})
    TestFixtures.class_type_fixture(%{tenant_context: staff})
    slot = TestFixtures.slot_fixture(workout, %{tenant_context: staff})

    {:ok, _} =
      SaveWorkoutGoals.call(staff, workout.id, %{
        "muscles" => [
          %{"id" => "quadriceps", "role" => "primary"},
          %{"id" => "hamstrings", "role" => "secondary"}
        ],
        "qualities" => ["stamina"]
      })

    %{
      org: org,
      owner: owner,
      staff: staff,
      coach: coach,
      front_desk: front_desk,
      member: member,
      workout: workout,
      slot: slot
    }
  end

  defp workout_path(ctx, id \\ nil),
    do: "/api/org/#{ctx.org.slug}/admin/workouts/#{id || ctx.workout.id}/goal-feedback-summary"

  defp class_path(ctx),
    do: "/api/org/#{ctx.org.slug}/admin/schedule/slots/#{ctx.slot.id}/goal-feedback-summary"

  defp get_as(conn, user, path), do: conn |> recycle() |> put_bearer_token(user) |> get(path)

  # Entries of members of the gym: `n` timed executions of the workout and one
  # training-log entry logged from the class, all reaching the coach.
  defp feedback!(ctx, n) do
    for _ <- 1..n//1 do
      {member, _} = member_context(ctx.org)

      execution =
        Repo.insert!(%WorkoutExecution{
          user_id: member.id,
          organization_id: ctx.org.id,
          master_workout_id: ctx.workout.id,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          completed_at_utc: DateTime.utc_now()
        })

      felt!(ctx, member, "execution", execution.id, ["vastus-medialis"])
    end
  end

  defp class_entry!(ctx, muscles) do
    {member, _} = member_context(ctx.org)

    entry =
      Repo.insert!(%TrainingLogEntry{
        user_id: member.id,
        organization_id: ctx.org.id,
        master_workout_id: ctx.workout.id,
        source_type: "class",
        source_reference_id: ctx.slot.id,
        title: "Class",
        performed_at_utc: DateTime.utc_now(),
        idempotency_key: Ecto.UUID.generate()
      })

    felt!(ctx, member, "training_log", entry.id, muscles)
  end

  defp felt!(ctx, member, kind, entry_id, muscles) do
    Repo.insert!(%GoalFeedback{
      user_id: member.id,
      organization_id: ctx.org.id,
      entry_kind: kind,
      entry_id: entry_id,
      felt_muscles: muscles,
      felt_qualities: ["stamina"]
    })
  end

  describe "workout summary" do
    test "a coach gets the totals from three entries up", %{conn: conn} = ctx do
      feedback!(ctx, 2)

      assert %{
               "entries" => 2,
               "shown" => false,
               "felt_muscles" => [],
               "felt_qualities" => [],
               "goals_not_felt" => []
             } = conn |> get_as(ctx.coach, workout_path(ctx)) |> json_response(200)

      feedback!(ctx, 1)

      assert %{
               "workout_id" => workout_id,
               "entries" => 3,
               "shown" => true,
               "felt_muscles" => [%{"id" => "quadriceps", "count" => 3}],
               "felt_qualities" => [%{"id" => "stamina", "count" => 3}],
               "goals_not_felt" => ["hamstrings"]
             } = conn |> get_as(ctx.coach, workout_path(ctx)) |> json_response(200)

      assert workout_id == ctx.workout.id
    end

    test "members and front desk cannot read it; unknown workouts are 404", %{conn: conn} = ctx do
      assert conn |> get_as(ctx.member, workout_path(ctx)) |> json_response(403)
      assert conn |> get_as(ctx.front_desk, workout_path(ctx)) |> json_response(403)

      assert conn
             |> get_as(ctx.coach, workout_path(ctx, Ecto.UUID.generate()))
             |> json_response(404)
    end
  end

  describe "class summary" do
    test "counts the class's entries for a coach", %{conn: conn} = ctx do
      feedback!(ctx, 2)
      for _ <- 1..3, do: class_entry!(ctx, ["hamstrings"])

      assert %{
               "scheduled_class_id" => slot_id,
               "workout_id" => workout_id,
               "entries" => 3,
               "shown" => true,
               "felt_muscles" => [%{"id" => "hamstrings", "count" => 3}],
               "goals_not_felt" => ["quadriceps"]
             } = conn |> get_as(ctx.coach, class_path(ctx)) |> json_response(200)

      assert slot_id == ctx.slot.id and workout_id == ctx.workout.id
    end

    test "front desk may ask but reads no one's feedback; members may not", %{conn: conn} = ctx do
      for _ <- 1..3, do: class_entry!(ctx, ["hamstrings"])

      assert %{"entries" => 0, "shown" => false} =
               conn |> get_as(ctx.front_desk, class_path(ctx)) |> json_response(200)

      assert conn |> get_as(ctx.member, class_path(ctx)) |> json_response(403)
    end
  end

  describe "goals default and inheritance" do
    test "the admin settings expose and change wod_goals_visible_by_default",
         %{conn: conn} = ctx do
      settings_path = "/api/org/#{ctx.org.slug}/admin/settings"

      assert %{"workouts" => %{"wod_goals_visible_by_default" => false}} =
               conn |> get_as(ctx.owner, settings_path) |> json_response(200)

      assert %{"workouts" => %{"wod_goals_visible_by_default" => true}} =
               conn
               |> recycle()
               |> put_bearer_token(ctx.owner)
               |> patch(settings_path, %{workouts: %{wod_goals_visible_by_default: true}})
               |> json_response(200)

      other = TestFixtures.workout_fixture(ctx.owner, %{tenant_context: ctx.staff})

      assert %{"goals" => %{"saved" => false, "visible_to_members" => true}} =
               conn
               |> get_as(ctx.coach, "/api/org/#{ctx.org.slug}/admin/workouts/#{other.id}/goals")
               |> json_response(200)
    end

    test "a variant names the workout its goals come from", %{conn: conn} = ctx do
      {:ok, draft} = DuplicateWorkout.call(ctx.staff, ctx.workout.id, copy_goals: false)

      {:ok, variant} =
        Workouts.publish_workout(ctx.staff, draft.id, %{expected_source_revision: 0})

      base_id = ctx.workout.id

      assert %{"goals" => %{"saved" => false, "inherited_from" => ^base_id}} =
               conn
               |> get_as(ctx.coach, "/api/org/#{ctx.org.slug}/admin/workouts/#{variant.id}/goals")
               |> json_response(200)

      assert %{"goals" => %{"saved" => true, "inherited_from" => nil}} =
               conn
               |> get_as(ctx.coach, "/api/org/#{ctx.org.slug}/admin/workouts/#{base_id}/goals")
               |> json_response(200)
    end
  end
end
