defmodule MilosTrainingWeb.MyWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Execution
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Messaging
  alias MilosTraining.Notifications
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workouts

  defp tenant_context_fixture(admin, name) do
    {:ok, organization} = Organizations.create_organization(%{name: name})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: admin.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, context} = Organizations.resolve_tenant_context(admin, organization.slug)
    {context, organization}
  end

  defp athlete_membership_fixture(context, athlete) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: context.organization_id,
        user_id: athlete.id,
        role: :athlete,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    athlete
  end

  defp tenant_workout_fixture(context, admin) do
    params = %{
      title: "Workout #{System.unique_integer([:positive])}",
      type: :crossfit,
      sections: [
        %{
          name: "Main Set",
          order: 1,
          scoreable: false,
          exercises: [
            %{
              name: "Air Squats",
              order: 1,
              sets: 3,
              prescription_value: 10,
              prescription_unit: "reps"
            }
          ]
        }
      ]
    }

    {:ok, workout} = Workouts.create_workout(context, admin, params)
    workout
  end

  test "athlete sees only their assigned workouts for the requested week", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_admin"})

    {context, organization} =
      tenant_context_fixture(admin, "My Workouts Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_athlete", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "my_workouts_other", role: :athlete})
    athlete_membership_fixture(context, athlete)
    athlete_membership_fixture(context, other)
    workout = tenant_workout_fixture(context, admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    {:ok, _other_assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [other.id],
        scheduled_for: monday
      })

    payload =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/org/#{organization.slug}/my-workouts?start_date=#{Date.to_iso8601(monday)}")
      |> json_response(200)

    assert payload["start_date"] == Date.to_iso8601(monday)
    assert length(payload["assignments"]) == 1
    refute Map.has_key?(hd(payload["assignments"]), "athlete_ids")
  end

  test "invalid start_date returns bad request", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_invalid_date_admin"})

    {context, organization} =
      tenant_context_fixture(admin, "Invalid Date Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_invalid_date", role: :athlete})
    athlete_membership_fixture(context, athlete)

    payload =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/org/#{organization.slug}/my-workouts?start_date=not-a-date")
      |> json_response(400)

    assert payload["code"] == "bad_request"
    assert payload["error"] == "Required parameter is missing or invalid"
  end

  test "admin sees athlete details on assigned workouts", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_admin_view"})

    {context, organization} =
      tenant_context_fixture(admin, "Admin View Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_named_athlete", role: :athlete})
    athlete_membership_fixture(context, athlete)
    workout = tenant_workout_fixture(context, admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    payload =
      conn
      |> put_bearer_token(admin)
      |> get("/api/org/#{organization.slug}/my-workouts?start_date=#{Date.to_iso8601(monday)}")
      |> json_response(200)

    [assignment] = payload["assignments"]
    [athlete_payload] = assignment["athletes"]

    assert athlete_payload["id"] == athlete.id
    assert athlete_payload["nickname"] == athlete.nickname
  end

  test "athlete can reschedule an assigned workout", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_reschedule_admin"})

    {context, organization} =
      tenant_context_fixture(admin, "Reschedule Gym #{System.unique_integer([:positive])}")

    athlete =
      TestFixtures.user_fixture(%{nickname: "my_workouts_reschedule_athlete", role: :athlete})

    athlete_membership_fixture(context, athlete)
    workout = tenant_workout_fixture(context, admin)
    original_date = Date.add(Date.utc_today(), 1)
    new_date = Date.add(Date.utc_today(), 3)

    {:ok, assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: original_date
      })

    payload =
      conn
      |> put_bearer_token(athlete)
      |> patch(
        "/api/org/#{organization.slug}/my-workouts/assignments/#{assignment.id}/reschedule",
        %{
          scheduled_for: Date.to_iso8601(new_date)
        }
      )
      |> json_response(200)

    assert payload["assignment"]["id"] == assignment.id
    assert payload["assignment"]["scheduled_for"] == Date.to_iso8601(new_date)
  end

  test "rescheduling a shared assignment changes only the requesting athlete", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "shared_reschedule_admin"})

    {context, organization} =
      tenant_context_fixture(admin, "Shared Reschedule Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "shared_reschedule_one", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "shared_reschedule_two", role: :athlete})
    athlete_membership_fixture(context, athlete)
    athlete_membership_fixture(context, other)
    workout = tenant_workout_fixture(context, admin)
    original_date = Date.add(Date.utc_today(), 1)
    new_date = Date.add(Date.utc_today(), 3)

    {:ok, assignment} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id, other.id],
        scheduled_for: original_date
      })

    conn
    |> put_bearer_token(athlete)
    |> patch(
      "/api/org/#{organization.slug}/my-workouts/assignments/#{assignment.id}/reschedule",
      %{
        scheduled_for: Date.to_iso8601(new_date)
      }
    )
    |> json_response(200)

    athlete_assignments =
      RepoContext.run(context, fn ->
        Workouts.list_assigned_workouts_for_athlete(athlete.id, new_date, new_date)
      end)

    other_assignments =
      RepoContext.run(context, fn ->
        Workouts.list_assigned_workouts_for_athlete(other.id, original_date, original_date)
      end)

    assert Enum.any?(athlete_assignments, &(&1.id == assignment.id))
    assert Enum.any?(other_assignments, &(&1.id == assignment.id))
  end

  test "athlete can request a workout assignment for a future date", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "assignment_request_admin"})

    {context, organization} =
      tenant_context_fixture(
        admin,
        "Assignment Request Gym #{System.unique_integer([:positive])}"
      )

    athlete = TestFixtures.user_fixture(%{nickname: "assignment_request_athlete", role: :athlete})
    athlete_membership_fixture(context, athlete)
    requested_for = Date.add(Date.utc_today(), 2)

    payload =
      conn
      |> put_bearer_token(athlete)
      |> post(
        "/api/org/#{organization.slug}/my-workouts/requests",
        %{
          requested_for: Date.to_iso8601(requested_for),
          note: "Prefer strength."
        }
      )
      |> json_response(202)

    assert payload["requested_for"] == Date.to_iso8601(requested_for)
    assert payload["notified_admins"] >= 1

    assert Messaging.list_threads_for_user(admin.id) == []

    assert [notification] = Notifications.list_for_user(admin.id)
    assert notification.type == "workout_assignment_requested"
    assert notification.payload["athlete_id"] == athlete.id
    assert notification.payload["requested_for"] == Date.to_iso8601(requested_for)
    assert notification.payload["note"] == "Prefer strength."

    assert notification.payload["url"] ==
             "/admin/coaching-assignments?date=#{Date.to_iso8601(requested_for)}"
  end

  test "workout assignment request rejects past dates", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "assignment_request_past_admin"})

    {context, organization} =
      tenant_context_fixture(admin, "Past Date Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "assignment_request_past", role: :athlete})
    athlete_membership_fixture(context, athlete)

    conn
    |> put_bearer_token(athlete)
    |> post(
      "/api/org/#{organization.slug}/my-workouts/requests",
      %{
        requested_for: Date.utc_today() |> Date.add(-1) |> Date.to_iso8601()
      }
    )
    |> json_response(422)
  end

  test "workout assignment request is athlete-only", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "request_forbidden_admin"})

    {_context, organization} =
      tenant_context_fixture(admin, "Forbidden Gym #{System.unique_integer([:positive])}")

    conn
    |> put_bearer_token(admin)
    |> post(
      "/api/org/#{organization.slug}/my-workouts/requests",
      %{
        requested_for: Date.utc_today() |> Date.add(1) |> Date.to_iso8601()
      }
    )
    |> json_response(403)
  end

  test "direct messaging threads between admin and each athlete are isolated", %{conn: _conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "shared_messages_admin"})

    {context, _organization} =
      tenant_context_fixture(admin, "Shared Messages Gym #{System.unique_integer([:positive])}")

    athlete = TestFixtures.user_fixture(%{nickname: "shared_messages_one", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "shared_messages_two", role: :athlete})
    athlete_membership_fixture(context, athlete)
    athlete_membership_fixture(context, other)

    {athlete_thread, other_thread, other_messages, athlete_messages} =
      Messaging.with_tenant_context(context, fn ->
        {:ok, athlete_thread} =
          MilosTraining.Messaging.get_or_create_thread(%{
            context_type: :direct,
            actor_id: admin.id,
            participant_id: athlete.id
          })

        {:ok, _msg} =
          MilosTraining.Messaging.send_message(%{
            thread_id: athlete_thread.id,
            sender_id: admin.id,
            body: "Private note",
            message_type: :coaching_note
          })

        {:ok, other_thread} =
          MilosTraining.Messaging.get_or_create_thread(%{
            context_type: :direct,
            actor_id: admin.id,
            participant_id: other.id
          })

        {:ok, other_messages} = MilosTraining.Messaging.list_messages(other_thread.id, %{})
        {:ok, athlete_messages} = MilosTraining.Messaging.list_messages(athlete_thread.id, %{})

        {athlete_thread, other_thread, other_messages, athlete_messages}
      end)

    refute athlete_thread.id == other_thread.id
    assert other_messages == []
    assert [%{body: "Private note"}] = athlete_messages
  end

  test "completion status is keyed by assignment rather than reused workout", %{conn: _conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "assignment_completion_admin"})

    {context, _organization} =
      tenant_context_fixture(admin, "Completion Gym #{System.unique_integer([:positive])}")

    athlete =
      TestFixtures.user_fixture(%{nickname: "assignment_completion_athlete", role: :athlete})

    athlete_membership_fixture(context, athlete)
    workout = tenant_workout_fixture(context, admin)
    first_date = Date.add(Date.utc_today(), 1)
    second_date = Date.add(Date.utc_today(), 2)

    {:ok, first} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: first_date,
        admin_notes: "First"
      })

    {:ok, second} =
      Workouts.assign_workout(context, %{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: second_date,
        admin_notes: "Second"
      })

    athlete_execution_context = %{organization_id: context.organization_id, user_id: athlete.id}

    assignments =
      RepoContext.run(athlete_execution_context, fn ->
        {:ok, execution} =
          Execution.start_execution(athlete.id, %{
            organization_id: context.organization_id,
            master_workout_id: workout.id,
            source: "assigned",
            source_reference_id: first.id,
            timezone: "UTC"
          })

        {:ok, _completed} = Execution.complete_execution(execution.id, athlete.id, %{})

        Workouts.list_assigned_workouts_for_athlete(athlete.id, first_date, second_date)
      end)

    assert Enum.find(assignments, &(&1.id == first.id)).execution_status == "completed"
    refute Map.has_key?(Enum.find(assignments, &(&1.id == second.id)), :execution_status)
  end
end
