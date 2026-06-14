defmodule MilosTrainingWeb.MyWorkoutControllerTest do
  use MilosTrainingWeb.ConnCase, async: false

  alias MilosTraining.Execution
  alias MilosTraining.TestFixtures
  alias MilosTraining.Workouts

  test "athlete sees only their assigned workouts for the requested week", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_admin"})
    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_athlete", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "my_workouts_other", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    {:ok, _other_assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [other.id],
        scheduled_for: monday
      })

    payload =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/my-workouts?start_date=#{Date.to_iso8601(monday)}")
      |> json_response(200)

    assert payload["start_date"] == Date.to_iso8601(monday)
    assert length(payload["assignments"]) == 1
    refute Map.has_key?(hd(payload["assignments"]), "athlete_ids")
  end

  test "invalid start_date returns bad request", %{conn: conn} do
    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_invalid_date", role: :athlete})

    payload =
      conn
      |> put_bearer_token(athlete)
      |> get("/api/my-workouts?start_date=not-a-date")
      |> json_response(400)

    assert payload["error"] == "Bad request"
  end

  test "admin sees athlete details on assigned workouts", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_admin_view"})
    athlete = TestFixtures.user_fixture(%{nickname: "my_workouts_named_athlete", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)
    monday = Date.utc_today() |> Date.beginning_of_week(:monday)

    {:ok, _assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: monday
      })

    payload =
      conn
      |> put_bearer_token(admin)
      |> get("/api/my-workouts?start_date=#{Date.to_iso8601(monday)}")
      |> json_response(200)

    [assignment] = payload["assignments"]
    [athlete_payload] = assignment["athletes"]

    assert athlete_payload["id"] == athlete.id
    assert athlete_payload["nickname"] == athlete.nickname
  end

  test "athlete can reschedule an assigned workout", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "my_workouts_reschedule_admin"})

    athlete =
      TestFixtures.user_fixture(%{nickname: "my_workouts_reschedule_athlete", role: :athlete})

    workout = TestFixtures.workout_fixture(admin)
    original_date = Date.add(Date.utc_today(), 1)
    new_date = Date.add(Date.utc_today(), 3)

    {:ok, assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: original_date
      })

    payload =
      conn
      |> put_bearer_token(athlete)
      |> patch("/api/my-workouts/assignments/#{assignment.id}/reschedule", %{
        scheduled_for: Date.to_iso8601(new_date)
      })
      |> json_response(200)

    assert payload["assignment"]["id"] == assignment.id
    assert payload["assignment"]["scheduled_for"] == Date.to_iso8601(new_date)
  end

  test "rescheduling a shared assignment changes only the requesting athlete", %{conn: conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "shared_reschedule_admin"})
    athlete = TestFixtures.user_fixture(%{nickname: "shared_reschedule_one", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "shared_reschedule_two", role: :athlete})
    workout = TestFixtures.workout_fixture(admin)
    original_date = Date.add(Date.utc_today(), 1)
    new_date = Date.add(Date.utc_today(), 3)

    {:ok, assignment} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id, other.id],
        scheduled_for: original_date
      })

    conn
    |> put_bearer_token(athlete)
    |> patch("/api/my-workouts/assignments/#{assignment.id}/reschedule", %{
      scheduled_for: Date.to_iso8601(new_date)
    })
    |> json_response(200)

    athlete_assignments =
      Workouts.list_assigned_workouts_for_athlete(athlete.id, new_date, new_date)

    other_assignments =
      Workouts.list_assigned_workouts_for_athlete(other.id, original_date, original_date)

    assert Enum.any?(athlete_assignments, &(&1.id == assignment.id))
    assert Enum.any?(other_assignments, &(&1.id == assignment.id))
  end

  test "direct messaging threads between admin and each athlete are isolated", %{conn: _conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "shared_messages_admin"})
    athlete = TestFixtures.user_fixture(%{nickname: "shared_messages_one", role: :athlete})
    other = TestFixtures.user_fixture(%{nickname: "shared_messages_two", role: :athlete})

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

    refute athlete_thread.id == other_thread.id

    {:ok, other_messages} = MilosTraining.Messaging.list_messages(other_thread.id, %{})
    assert other_messages == []

    {:ok, athlete_messages} = MilosTraining.Messaging.list_messages(athlete_thread.id, %{})
    assert [%{body: "Private note"}] = athlete_messages
  end

  test "completion status is keyed by assignment rather than reused workout", %{conn: _conn} do
    admin = TestFixtures.admin_fixture(%{nickname: "assignment_completion_admin"})

    athlete =
      TestFixtures.user_fixture(%{nickname: "assignment_completion_athlete", role: :athlete})

    workout = TestFixtures.workout_fixture(admin)
    first_date = Date.add(Date.utc_today(), 1)
    second_date = Date.add(Date.utc_today(), 2)

    {:ok, first} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: first_date,
        admin_notes: "First"
      })

    {:ok, second} =
      Workouts.assign_workout(%{
        master_workout_id: workout.id,
        athlete_ids: [athlete.id],
        scheduled_for: second_date,
        admin_notes: "Second"
      })

    {:ok, execution} =
      Execution.start_execution(athlete.id, %{
        master_workout_id: workout.id,
        source: "assigned",
        source_reference_id: first.id,
        timezone: "UTC"
      })

    {:ok, _completed} = Execution.complete_execution(execution.id, athlete.id, %{})

    assignments =
      Workouts.list_assigned_workouts_for_athlete(athlete.id, first_date, second_date)

    assert Enum.find(assignments, &(&1.id == first.id)).execution_status == "completed"
    refute Map.has_key?(Enum.find(assignments, &(&1.id == second.id)), :execution_status)
  end
end
