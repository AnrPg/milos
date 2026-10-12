defmodule MilosTraining.Application.GetTrainingLogTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.GetTrainingLog
  alias MilosTraining.Execution.WorkoutExecution
  alias MilosTraining.{Organizations, Repo}
  alias MilosTraining.Scheduling.{Booking, ClassAttendanceRecord, ScheduledClass}

  setup do
    admin = admin_fixture()
    member = user_fixture(%{role: :member})

    {:ok, organization} =
      Organizations.create_organization(%{name: "Log Gym #{System.unique_integer([:positive])}"})

    for {user, role} <- [{admin, :owner}, {member, :member}] do
      {:ok, _membership} =
        Organizations.add_membership(%{
          organization_id: organization.id,
          user_id: user.id,
          role: role,
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    {:ok, member_context} = Organizations.resolve_tenant_context(member, organization.slug)

    workout =
      workout_fixture(admin, %{
        tenant_context: context,
        title: "Fran",
        sections: [
          %{
            name: "21-15-9",
            order: 1,
            scoreable: true,
            score_config: %{type: "time"},
            timer_config: %{type: "ladder_descending", start_reps: 21, step_reps: 6, min_reps: 9},
            exercises: [%{name: "Thruster", order: 1, load_value: 43, load_mode: "absolute"}]
          }
        ]
      })

    class_type = class_type_fixture(%{tenant_context: context})

    %{
      organization: organization,
      context: context,
      member_context: member_context,
      member: member,
      workout: workout,
      class_type: class_type
    }
  end

  defp execution!(ctx, attrs) do
    {scores, attrs} = Map.pop(attrs, :section_scores, [])

    %WorkoutExecution{organization_id: ctx.organization.id}
    |> WorkoutExecution.start_changeset(
      Map.merge(
        %{
          user_id: ctx.member.id,
          master_workout_id: ctx.workout.id,
          source: :self_selected,
          status: :completed,
          started_at_utc: DateTime.utc_now(),
          started_at_tz: "UTC"
        },
        attrs
      )
    )
    |> Ecto.Changeset.put_change(:section_scores, scores)
    |> Repo.insert!()
  end

  test "workouts are paged newest first with the workout and the performance", ctx do
    section = hd(ctx.workout.sections)

    for days_ago <- 1..3 do
      execution!(ctx, %{
        started_at_utc: DateTime.add(DateTime.utc_now(), -days_ago, :day),
        section_scores: [
          %{"section_id" => section.id, "value" => "#{days_ago}:30", "unit" => "min"}
        ]
      })
    end

    assert {:ok, page} =
             GetTrainingLog.call(ctx.context, ctx.member.id, %{
               "kind" => "workouts",
               "limit" => "2"
             })

    assert page.total == 3
    assert page.next_offset == 2
    assert [first, _second] = page.entries
    assert first.workout.title == "Fran"
    assert [%{format: "ladder_descending", score_type: "time"}] = first.workout.sections

    assert [%{section_name: "21-15-9", score_type: "time", value: "1:30"}] =
             first.performance.scores

    assert {:ok, %{entries: [last], next_offset: nil}} =
             GetTrainingLog.call(ctx.context, ctx.member.id, %{
               "kind" => "workouts",
               "offset" => 2
             })

    assert hd(last.performance.scores).value == "3:30"

    # The member sees the same log on their own profile.
    assert {:ok, %{total: 3}} =
             GetTrainingLog.call(ctx.member_context, ctx.member.id, %{"kind" => "workouts"})
  end

  test "classes show the booked class, its workout, attendance and the member's result", ctx do
    slot =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization.id,
        master_workout_id: ctx.workout.id,
        class_type_id: ctx.class_type.id,
        name: "Evening WOD",
        scheduled_at: DateTime.add(DateTime.utc_now(), -2, :day) |> DateTime.truncate(:second),
        capacity: 10
      })

    booking =
      Repo.insert!(%Booking{
        organization_id: ctx.organization.id,
        scheduled_class_id: slot.id,
        user_id: ctx.member.id,
        status: :approved
      })

    Repo.insert!(%ClassAttendanceRecord{
      organization_id: ctx.organization.id,
      scheduled_class_id: slot.id,
      booking_id: booking.id,
      user_id: ctx.member.id,
      status: "attended",
      marked_at: DateTime.utc_now()
    })

    # A future booking is not history yet.
    future =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization.id,
        master_workout_id: ctx.workout.id,
        class_type_id: ctx.class_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), 2, :day) |> DateTime.truncate(:second),
        capacity: 10
      })

    Repo.insert!(%Booking{
      organization_id: ctx.organization.id,
      scheduled_class_id: future.id,
      user_id: ctx.member.id,
      status: :approved
    })

    execution!(ctx, %{
      source: :class_booking,
      source_reference_id: booking.id,
      section_scores: [%{"section_id" => hd(ctx.workout.sections).id, "value" => "4:12"}]
    })

    assert {:ok, %{total: 1, entries: [entry]}} =
             GetTrainingLog.call(ctx.context, ctx.member.id, %{"kind" => "classes"})

    assert entry.class.name == "Evening WOD"
    assert entry.class.attendance == "attended"
    assert entry.workout.title == "Fran"
    assert [%{value: "4:12", section_name: "21-15-9"}] = entry.performance.scores
  end

  test "a class without a logged result still appears", ctx do
    slot =
      Repo.insert!(%ScheduledClass{
        organization_id: ctx.organization.id,
        master_workout_id: ctx.workout.id,
        class_type_id: ctx.class_type.id,
        scheduled_at: DateTime.add(DateTime.utc_now(), -1, :day) |> DateTime.truncate(:second),
        capacity: 10
      })

    Repo.insert!(%Booking{
      organization_id: ctx.organization.id,
      scheduled_class_id: slot.id,
      user_id: ctx.member.id,
      status: :approved
    })

    assert {:ok, %{entries: [%{performance: nil, workout: %{title: "Fran"}}]}} =
             GetTrainingLog.call(ctx.context, ctx.member.id, %{"kind" => "classes"})

    assert {:error, :invalid_history_kind} =
             GetTrainingLog.call(ctx.context, ctx.member.id, %{"kind" => "other"})
  end
end
