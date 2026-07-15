defmodule MilosTraining.CoachingTest do
  use MilosTraining.DataCase

  alias MilosTraining.{Coaching, Execution.WorkoutExecution, TestFixtures}

  test "coaching aggregates separate active and inactive athletes" do
    active_athlete = TestFixtures.user_fixture(%{role: :athlete})
    inactive_athlete = TestFixtures.user_fixture(%{role: :athlete})
    _member = TestFixtures.user_fixture(%{role: :member})

    completed_at = DateTime.add(DateTime.utc_now(), -7, :day)

    %WorkoutExecution{}
    |> WorkoutExecution.start_changeset(%{
      user_id: active_athlete.id,
      source: :self_selected,
      status: :completed,
      started_at_utc: DateTime.add(completed_at, -1800, :second),
      started_at_tz: "UTC"
    })
    |> Ecto.Changeset.put_change(:completed_at_utc, completed_at)
    |> Ecto.Changeset.put_change(:completed_at_tz, "UTC")
    |> Repo.insert!()

    assert :ok = Coaching.refresh_aggregates()
    aggregates = Coaching.get_aggregates()

    assert aggregates.active_athlete_count == 1
    assert aggregates.inactive_athlete_count == 1
    assert aggregates.completed_workouts_this_week >= 0
    refute aggregates.active_athlete_count + aggregates.inactive_athlete_count < 2
    refute inactive_athlete.id == active_athlete.id
  end
end
