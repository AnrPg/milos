defmodule Palee.Application.InjuryWarningsTest do
  @moduledoc """
  ADR-124 injury-aware workout safety warnings: staff vs self visibility
  across two tenants and personal (self-reported) injuries, the class roster
  path, analytics segmentation and completion facts. Runs as the
  RLS-enforcing runtime role; fixtures model pre-existing data.
  """
  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.AnalyticsHelpers

  alias Palee.Application.{
    AcknowledgeAthleteInjuryWarnings,
    AcknowledgeMyInjuryWarnings,
    AdminReportInjury,
    CompleteWorkout,
    EvaluateAthleteInjuryWarnings,
    GetMyWorkoutInjuryWarnings,
    InjuryWarningEvaluation,
    ListClassSlotInjuryWarnings,
    LogTrainingEntry,
    ReportInjury,
    StartWorkoutExecution,
    SweepAbandonedExecutions
  }

  alias Palee.Execution.WorkoutExecution
  alias Palee.{Organizations, Repo, Scheduling, TestFixtures, Workouts}

  import Ecto.Query, only: [where: 3]

  # TD-088: Box Jump and Back Squat load the knee at Rx; the "scaled" level
  # swaps the jump for a plank and drops the squat.
  defp scaled_workout!(context, owner) do
    {:ok, _levels} = Workouts.seed_default_scale_levels(context)

    {:ok, workout} =
      Workouts.create_workout(context, owner, %{
        title: "Scaled injury WOD #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises: [
              %{
                name: "Box Jump",
                order: 1,
                prescription_value: 10,
                prescription_unit: "reps",
                variations: [%{scale_level_slug: "scaled", exercise_name_override: "Plank"}]
              },
              %{
                name: "Back Squat",
                order: 2,
                prescription_value: 5,
                prescription_unit: "reps",
                variations: [%{scale_level_slug: "scaled", excluded: true}]
              },
              %{name: "Strict Press", order: 3, prescription_value: 5, prescription_unit: "reps"}
            ]
          }
        ]
      })

    workout
  end

  defp backdate!(execution_id, hours) do
    started_at = DateTime.add(DateTime.utc_now(), -hours * 3_600, :second)

    bypass_rls(fn ->
      {1, _} =
        WorkoutExecution
        |> where([e], e.id == ^execution_id)
        |> Repo.update_all(set: [started_at_utc: started_at])
    end)
  end

  defp knee_member!(ctx) do
    bypass_rls(fn ->
      {member, member_context} = member_context(ctx.org_a)
      admin_injury!(ctx.staff_a, ctx.owner_a, member, %{"body_area" => "knee"})
      {member, member_context}
    end)
  end

  defp workout!(context, owner, exercises) do
    {:ok, workout} =
      Workouts.create_workout(context, owner, %{
        title: "Injury WOD #{System.unique_integer([:positive])}",
        type: :crossfit,
        sections: [
          %{
            name: "Main",
            order: 1,
            scoreable: false,
            exercises:
              exercises
              |> Enum.with_index(1)
              |> Enum.map(fn {name, order} ->
                %{
                  name: name,
                  order: order,
                  sets: 3,
                  prescription_value: 10,
                  prescription_unit: "reps"
                }
              end)
          }
        ]
      })

    workout
  end

  defp admin_injury!(context, owner, athlete, attrs) do
    {:ok, injury} =
      AdminReportInjury.call(
        context,
        owner.id,
        athlete.id,
        Map.merge(%{"severity" => "moderate", "visibility" => "user_and_admin"}, attrs)
      )

    injury
  end

  # A self-report the member keeps to themselves (ADR-286 switch off); shared
  # ones are covered in InjuryWarningControllerTest.
  defp personal_injury!(athlete_context, athlete, attrs) do
    {:ok, injury} =
      ReportInjury.call(
        athlete_context,
        athlete.id,
        Map.merge(%{"severity" => "moderate", "shared_with_box" => false}, attrs)
      )

    injury
  end

  defp areas(warnings), do: warnings |> Enum.map(& &1.body_area) |> Enum.sort()

  defp slot!(ctx) do
    class_type = TestFixtures.class_type_fixture(%{tenant_context: ctx.staff_a})

    TestFixtures.slot_fixture(ctx.workout_a, %{
      tenant_context: ctx.staff_a,
      class_type_id: class_type.id
    })
  end

  setup do
    bypass_rls(fn ->
      {org_a, owner_a, staff_a} = organization_fixture()
      {org_b, owner_b, staff_b} = organization_fixture()

      athlete = TestFixtures.user_fixture(%{role: :athlete})
      add_membership(org_a, athlete, :athlete)
      add_membership(org_b, athlete, :athlete)
      {:ok, athlete_a} = Organizations.resolve_tenant_context(athlete, org_a.slug)

      exercises = ["Back Squat", "Strict Press", "Run", "Deadlift"]
      workout_a = workout!(staff_a, owner_a, exercises)
      workout_b = workout!(staff_b, owner_b, exercises)

      knee = admin_injury!(staff_a, owner_a, athlete, %{"body_area" => "knee"})

      hidden_shoulder =
        admin_injury!(staff_a, owner_a, athlete, %{
          "body_area" => "shoulder",
          "visibility" => "admin_only",
          "training_limitations" => "No pressing above the head"
        })

      ankle =
        admin_injury!(staff_b, owner_b, athlete, %{"body_area" => "ankle", "severity" => "severe"})

      back = personal_injury!(athlete_a, athlete, %{"body_area" => "lower back"})

      %{
        org_a: org_a,
        org_b: org_b,
        owner_a: owner_a,
        staff_a: staff_a,
        staff_b: staff_b,
        athlete: athlete,
        athlete_a: athlete_a,
        workout_a: workout_a,
        workout_b: workout_b,
        injuries: %{knee: knee, hidden_shoulder: hidden_shoulder, ankle: ankle, back: back}
      }
    end)
  end

  describe "staff evaluation" do
    test "only sees the acting tenant's injuries, including admin-only ones", ctx do
      assert {:ok, result} =
               EvaluateAthleteInjuryWarnings.call(ctx.staff_a, %{
                 workout_id: ctx.workout_a.id,
                 user_ids: [ctx.athlete.id],
                 surface: "assign_dialog"
               })

      assert [%{user_id: user_id, level: :avoid, warnings: warnings}] = result.athletes
      assert user_id == ctx.athlete.id
      assert areas(warnings) == ["knee", "shoulder"]
      assert Enum.all?(warnings, &(&1.provenance == :organization))

      shoulder = Enum.find(warnings, &(&1.body_area == "shoulder"))
      assert shoulder.training_limitations == "No pressing above the head"

      assert Enum.any?(
               shoulder.exercises,
               &(&1.exercise_ref == "strict-press" and &1.level == :avoid)
             )
    end

    test "the other tenant's staff see only their own report, never the personal one", ctx do
      assert {:ok, %{athletes: [%{warnings: warnings}]}} =
               EvaluateAthleteInjuryWarnings.call(ctx.staff_b, %{
                 workout_id: ctx.workout_b.id,
                 user_ids: [ctx.athlete.id]
               })

      assert areas(warnings) == ["ankle"]
    end

    test "cannot evaluate another tenant's workout", ctx do
      assert {:error, :not_found} =
               EvaluateAthleteInjuryWarnings.call(ctx.staff_b, %{
                 workout_id: ctx.workout_a.id,
                 user_ids: [ctx.athlete.id]
               })
    end

    test "users without injuries come back with no warnings and fail closed without a tenant",
         ctx do
      other = bypass_rls(fn -> TestFixtures.user_fixture(%{role: :athlete}) end)

      assert {:ok, %{athletes: [_athlete, %{user_id: other_id, level: :none, warnings: []}]}} =
               EvaluateAthleteInjuryWarnings.call(ctx.staff_a, %{
                 workout_id: ctx.workout_a.id,
                 user_ids: [ctx.athlete.id, other.id, "not-a-uuid"]
               })

      assert other_id == other.id

      assert {:error, :organization_context_required} =
               EvaluateAthleteInjuryWarnings.call(nil, %{
                 workout_id: ctx.workout_a.id,
                 user_ids: []
               })
    end

    test "records shown once per athlete/surface/day and acknowledgements on demand", ctx do
      params = %{
        workout_id: ctx.workout_a.id,
        user_ids: [ctx.athlete.id],
        surface: "assign_dialog"
      }

      {:ok, _} = EvaluateAthleteInjuryWarnings.call(ctx.staff_a, params)
      {:ok, _} = EvaluateAthleteInjuryWarnings.call(ctx.staff_a, params)

      shown = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "injury_warning_shown") end)
      assert shown.context_type == "workout"
      assert shown.context_id == ctx.workout_a.id
      assert shown.user_id == ctx.owner_a.id

      assert shown.metadata == %{
               "audience" => "staff",
               "surface" => "assign_dialog",
               "athlete_id" => ctx.athlete.id,
               "warning_level" => "avoid",
               "injury_warning_count" => 2,
               "avoid_exercise_count" => shown.metadata["avoid_exercise_count"],
               "caution_exercise_count" => shown.metadata["caution_exercise_count"]
             }

      refute Map.has_key?(shown.metadata, "body_area")

      assert {:ok, %{acknowledged_count: 1}} =
               AcknowledgeAthleteInjuryWarnings.call(ctx.staff_a, params)

      ack = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "injury_warning_acknowledged") end)
      assert ack.metadata["athlete_id"] == ctx.athlete.id
      assert ack.metadata["audience"] == "staff"

      assert bypass_rls(fn -> analytics_events(ctx.org_b.id, "injury_warning_shown") end) == []
    end
  end

  describe "class roster" do
    test "evaluates booked members against the slot's workout", ctx do
      slot =
        bypass_rls(fn ->
          slot = slot!(ctx)
          {:ok, _booking} = Scheduling.submit_booking(ctx.athlete_a, ctx.athlete.id, slot.id, 60)
          slot
        end)

      assert {:ok, result} = ListClassSlotInjuryWarnings.call(ctx.staff_a, slot.id)
      assert result.slot_id == slot.id
      assert result.workout_id == ctx.workout_a.id
      assert [%{user_id: user_id, warnings: warnings}] = result.athletes
      assert user_id == ctx.athlete.id
      assert areas(warnings) == ["knee", "shoulder"]

      shown = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "injury_warning_shown") end)
      assert shown.metadata["surface"] == "class_roster"
      assert shown.metadata["source_context_id"] == slot.id
    end

    test "another tenant's slot is not found", ctx do
      slot =
        bypass_rls(fn ->
          slot!(ctx)
        end)

      assert {:error, :not_found} = ListClassSlotInjuryWarnings.call(ctx.staff_b, slot.id)
      assert {:error, :not_found} = ListClassSlotInjuryWarnings.call(ctx.staff_a, "nope")
    end
  end

  describe "self evaluation" do
    test "the athlete sees every own visible injury, including personal ones", ctx do
      assert {:ok, result} =
               GetMyWorkoutInjuryWarnings.call(ctx.athlete_a, ctx.workout_a.id, %{
                 "surface" => "assignment_detail"
               })

      # knee (this gym), ankle (other gym) and the personal lower back; the
      # admin-only shoulder note stays hidden from the athlete.
      assert areas(result.warnings) == ["ankle", "knee", "lower back"]
      assert result.level == :avoid

      personal = Enum.find(result.warnings, &(&1.body_area == "lower back"))
      assert personal.provenance == :personal
    end

    test "analytics count only this tenant's injuries", ctx do
      {:ok, _} =
        GetMyWorkoutInjuryWarnings.call(ctx.athlete_a, ctx.workout_a.id, %{
          "surface" => "pre_start"
        })

      shown = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "injury_warning_shown") end)
      assert shown.user_id == ctx.athlete.id
      assert shown.metadata["audience"] == "self"
      assert shown.metadata["surface"] == "pre_start"
      assert shown.metadata["injury_warning_count"] == 1

      {:ok, %{level: :avoid, warning_count: 3}} =
        AcknowledgeMyInjuryWarnings.call(ctx.athlete_a, ctx.workout_a.id, %{
          "surface" => "pre_start"
        })

      ack = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "injury_warning_acknowledged") end)
      assert ack.metadata["injury_warning_count"] == 1
    end

    test "a personal-only injury warns the athlete but never reaches tenant analytics", ctx do
      {member, member_context} =
        bypass_rls(fn ->
          {member, member_context} = member_context(ctx.org_a)
          personal_injury!(member_context, member, %{"body_area" => "knee"})
          {member, member_context}
        end)

      assert {:ok, %{level: :avoid, warnings: [%{provenance: :personal}]}} =
               GetMyWorkoutInjuryWarnings.call(member_context, ctx.workout_a.id)

      assert {:ok, %{athletes: [%{level: :none}]}} =
               EvaluateAthleteInjuryWarnings.call(ctx.staff_a, %{
                 workout_id: ctx.workout_a.id,
                 user_ids: [member.id]
               })

      events = bypass_rls(fn -> analytics_events(ctx.org_a.id, "injury_warning_shown") end)
      refute Enum.any?(events, &(&1.user_id == member.id))
    end
  end

  describe "completion segmentation" do
    test "facts reflect organization-provenance injuries only", ctx do
      workout = bypass_rls(fn -> Workouts.get_workout(ctx.staff_a, ctx.workout_a.id) end)

      assert InjuryWarningEvaluation.completion_facts(
               %{organization_id: ctx.org_a.id, user_id: ctx.athlete.id},
               workout
             ) == %{had_active_injury: true, injury_warning_level: "avoid"}

      {member, _member_context} =
        bypass_rls(fn ->
          {member, member_context} = member_context(ctx.org_a)
          personal_injury!(member_context, member, %{"body_area" => "knee"})
          {member, member_context}
        end)

      assert InjuryWarningEvaluation.completion_facts(
               %{organization_id: ctx.org_a.id, user_id: member.id},
               workout
             ) == %{had_active_injury: false, injury_warning_level: "none"}

      assert InjuryWarningEvaluation.completion_facts(%{organization_id: nil}, workout) == %{}
    end

    test "workout_execution_completed carries the injury facts", ctx do
      {member, member_context} =
        bypass_rls(fn ->
          {member, member_context} = member_context(ctx.org_a)
          admin_injury!(ctx.staff_a, ctx.owner_a, member, %{"body_area" => "knee"})
          {member, member_context}
        end)

      {:ok, execution} =
        StartWorkoutExecution.call(member_context, member, %{
          "master_workout_id" => ctx.workout_a.id,
          "source" => "self_selected"
        })

      {:ok, _completed} =
        CompleteWorkout.call(member_context, execution.id, member.id, %{"section_scores" => []})

      event = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "workout_execution_completed") end)
      assert event.metadata["had_active_injury"] == true
      assert event.metadata["injury_warning_level"] == "avoid"
    end
  end

  describe "scaled variations (TD-088)" do
    test "the athlete's scale is evaluated, not only the Rx exercises", ctx do
      workout = bypass_rls(fn -> scaled_workout!(ctx.staff_a, ctx.owner_a) end)
      {_member, member_context} = knee_member!(ctx)

      assert {:ok, rx} = GetMyWorkoutInjuryWarnings.call(member_context, workout.id)
      assert rx.level == :avoid
      assert rx.scale_level_slug == nil
      assert [%{exercises: rx_exercises}] = rx.warnings

      assert rx_exercises |> Enum.map(& &1.name) |> Enum.sort() == ["Back Squat", "Box Jump"]

      assert {:ok, scaled} =
               GetMyWorkoutInjuryWarnings.call(member_context, workout.id, %{
                 "surface" => "pre_start",
                 "scale" => "scaled"
               })

      assert scaled.scale_level_slug == "scaled"
      assert scaled.level == :none
      assert scaled.warnings == []

      # A malformed scale falls back to Rx instead of erroring.
      assert {:ok, %{level: :avoid, scale_level_slug: nil}} =
               GetMyWorkoutInjuryWarnings.call(member_context, workout.id, %{
                 "scale" => "Not A Slug!"
               })
    end

    test "completion facts follow the executed scale", ctx do
      workout = bypass_rls(fn -> scaled_workout!(ctx.staff_a, ctx.owner_a) end)
      {member, member_context} = knee_member!(ctx)

      {:ok, execution} =
        StartWorkoutExecution.call(member_context, member, %{
          "master_workout_id" => workout.id,
          "source" => "self_selected",
          "scale_level_slug" => "scaled"
        })

      assert execution.scale_level_slug == "scaled"

      {:ok, _completed} =
        CompleteWorkout.call(member_context, execution.id, member.id, %{"section_scores" => []})

      event = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "workout_execution_completed") end)
      assert event.metadata["had_active_injury"] == true
      assert event.metadata["injury_warning_level"] == "none"
    end
  end

  describe "abandoned executions and training-log entries (TD-088)" do
    test "the ready screen's shown/acknowledged warnings are joined to the abandoned execution",
         ctx do
      {member, member_context} = knee_member!(ctx)

      start = fn ->
        {:ok, execution} =
          StartWorkoutExecution.call(member_context, member, %{
            "master_workout_id" => ctx.workout_a.id,
            "source" => "self_selected"
          })

        execution
      end

      warned = start.()
      unwarned = start.()
      params = %{"surface" => "pre_start", "source_context_id" => warned.id}

      {:ok, _} = GetMyWorkoutInjuryWarnings.call(member_context, ctx.workout_a.id, params)
      {:ok, _} = AcknowledgeMyInjuryWarnings.call(member_context, ctx.workout_a.id, params)

      # Ready-screen events are recorded once per execution, not once per day.
      {:ok, _} =
        GetMyWorkoutInjuryWarnings.call(member_context, ctx.workout_a.id, %{
          "surface" => "pre_start",
          "source_context_id" => Ecto.UUID.generate()
        })

      shown = bypass_rls(fn -> analytics_events(ctx.org_a.id, "injury_warning_shown") end)
      assert length(Enum.filter(shown, &(&1.user_id == member.id))) == 2

      backdate!(warned.id, 7)
      backdate!(unwarned.id, 7)

      assert {:ok, 2} = SweepAbandonedExecutions.call(ctx.org_a.id)

      events =
        bypass_rls(fn -> analytics_events(ctx.org_a.id, "workout_execution_abandoned") end)

      by_execution = Map.new(events, &{&1.context_id, &1.metadata})

      assert %{
               "had_active_injury" => true,
               "injury_warning_level" => "avoid",
               "injury_warning_shown" => true,
               "injury_warning_acknowledged" => true
             } = by_execution[warned.id]

      assert %{
               "had_active_injury" => true,
               "injury_warning_level" => "avoid",
               "injury_warning_shown" => false,
               "injury_warning_acknowledged" => false
             } = by_execution[unwarned.id]
    end

    test "abandonment facts never reflect a personal-only injury", ctx do
      {member, member_context} =
        bypass_rls(fn ->
          {member, member_context} = member_context(ctx.org_a)
          personal_injury!(member_context, member, %{"body_area" => "knee"})
          {member, member_context}
        end)

      {:ok, execution} =
        StartWorkoutExecution.call(member_context, member, %{
          "master_workout_id" => ctx.workout_a.id,
          "source" => "self_selected"
        })

      params = %{"surface" => "pre_start", "source_context_id" => execution.id}

      {:ok, %{level: :avoid}} =
        GetMyWorkoutInjuryWarnings.call(member_context, ctx.workout_a.id, params)

      backdate!(execution.id, 7)
      assert {:ok, 1} = SweepAbandonedExecutions.call(ctx.org_a.id)

      event = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "workout_execution_abandoned") end)

      assert %{
               "had_active_injury" => false,
               "injury_warning_level" => "none",
               "injury_warning_shown" => false
             } = event.metadata
    end

    test "training_log_entry_logged carries the injury facts of the logged workout", ctx do
      {member, member_context} = knee_member!(ctx)

      assert {:ok, entry, :created} =
               LogTrainingEntry.call(member_context, member, %{
                 "source_type" => "library_workout",
                 "source_reference_id" => ctx.workout_a.id,
                 "performed_at" =>
                   DateTime.utc_now() |> DateTime.add(-3_600) |> DateTime.to_iso8601(),
                 "duration_seconds" => 1_200,
                 "idempotency_key" => Ecto.UUID.generate()
               })

      logged = bypass_rls(fn -> analytics_event!(ctx.org_a.id, "training_log_entry_logged") end)
      assert logged.context_id == entry.id
      assert logged.metadata["had_active_injury"] == true
      assert logged.metadata["injury_warning_level"] == "avoid"
      refute Map.has_key?(logged.metadata, "body_area")
    end
  end
end
