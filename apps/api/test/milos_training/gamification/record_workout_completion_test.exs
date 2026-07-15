defmodule MilosTraining.Gamification.RecordWorkoutCompletionTest do
  use MilosTraining.DataCase, async: false

  import MilosTraining.TestFixtures

  alias MilosTraining.Application.CompleteWorkout
  alias MilosTraining.Execution
  alias MilosTraining.Gamification

  test "completion updates stats, awards PR events, advances challenges, and refreshes the leaderboard" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})

    {:ok, challenge} =
      Gamification.create_seasonal_challenge(admin.id, %{
        title: "June Builder",
        description: "Complete two workouts",
        criteria_type: "workout_count",
        criteria_value: %{count: 2},
        badge_key: "challenge_june_builder",
        badge_label: "June Builder",
        starts_at: Date.utc_today(),
        ends_at: Date.add(Date.utc_today(), 7)
      })

    {workout, section_id} = scoreable_workout!(admin)
    {:ok, _preference} = Gamification.set_leaderboard_opt_in(athlete.id, true)

    execution_one = complete_execution!(athlete.id, workout.id, section_id, 300)
    wait_for_gamification(athlete.id, fn stats -> stats.total_workouts == 1 end)

    execution_two = complete_execution!(athlete.id, workout.id, section_id, 250)

    wait_for_gamification(athlete.id, fn stats ->
      stats.total_workouts == 2 and stats.total_prs >= 1
    end)

    wait_for_leaderboard(athlete.id)

    stats = Gamification.get_user_stats(athlete.id)
    badges = Gamification.list_visible_achievements(athlete.id)
    leaderboard = Gamification.get_leaderboard("weekly", 5)
    progress = Gamification.challenge_progress(athlete.id, challenge.id)

    assert execution_one.id != execution_two.id
    assert stats.current_streak == 1
    assert stats.total_workouts == 2
    assert stats.total_prs >= 1
    assert progress.progress == 2
    assert not is_nil(progress.completed_at)
    assert Enum.any?(badges, &(&1.badge_key == "workouts_1"))
    assert Enum.any?(badges, &(&1.badge_key == "prs_1"))
    assert Enum.any?(badges, &(&1.badge_key == "challenge_june_builder"))
    assert Enum.any?(leaderboard, &(&1.user_id == athlete.id))
  end

  test "leaderboard counts are not multiplied by joined achievements" do
    admin = admin_fixture()
    athlete = user_fixture(%{role: :athlete})
    {workout, section_id} = scoreable_workout!(admin)

    {:ok, _preference} = Gamification.set_leaderboard_opt_in(athlete.id, true)

    _first = complete_execution!(athlete.id, workout.id, section_id, "05:00")
    _second = complete_execution!(athlete.id, workout.id, section_id, "04:40")

    wait_for_gamification(athlete.id, fn stats ->
      stats.total_workouts == 2 and stats.total_prs >= 1
    end)

    _ = Gamification.refresh_leaderboard()

    leaderboard_entry =
      Enum.find(Gamification.get_leaderboard("weekly", 5), &(&1.user_id == athlete.id))

    assert leaderboard_entry.workouts_this_week == 2
    assert leaderboard_entry.prs_this_month == 1
  end

  defp complete_execution!(user_id, workout_id, section_id, score_value) do
    {:ok, execution} =
      Execution.start_execution(user_id, %{
        master_workout_id: workout_id,
        source: "self_selected",
        timezone: "UTC"
      })

    {:ok, completed} =
      Execution.complete_execution(execution.id, user_id, %{
        timezone: "UTC",
        section_scores: [%{section_id: section_id, value: score_value, unit: "sec"}]
      })

    :ok = CompleteWorkout.process_completion(completed)

    completed
  end

  defp wait_for_gamification(user_id, predicate, attempts \\ 20)

  defp wait_for_gamification(user_id, predicate, attempts) when attempts > 0 do
    stats = Gamification.get_user_stats(user_id) || %{total_workouts: 0, total_prs: 0}

    if predicate.(stats) do
      :ok
    else
      Process.sleep(20)
      wait_for_gamification(user_id, predicate, attempts - 1)
    end
  end

  defp wait_for_gamification(_user_id, _predicate, 0),
    do: flunk("gamification event did not finish in time")

  defp wait_for_leaderboard(user_id, attempts \\ 20)

  defp wait_for_leaderboard(user_id, attempts) when attempts > 0 do
    leaderboard = Gamification.get_leaderboard("weekly", 5)

    if Enum.any?(leaderboard, &(&1.user_id == user_id)) do
      :ok
    else
      Process.sleep(20)
      wait_for_leaderboard(user_id, attempts - 1)
    end
  end

  defp wait_for_leaderboard(_user_id, 0),
    do: flunk("leaderboard refresh did not finish in time")

  defp scoreable_workout!(admin) do
    {:ok, workout} =
      MilosTraining.Workouts.create_workout(admin, %{
        title: "Scoreable Hero",
        type: :crossfit,
        sections: [
          %{
            name: "Main Piece",
            order: 1,
            scoreable: true,
            score_config: %{type: "time", unit: "sec", label: "Time"},
            exercises: [
              %{
                name: "Burpees",
                order: 1,
                prescription_value: 21,
                prescription_unit: "reps"
              }
            ]
          }
        ]
      })

    {workout, workout.sections |> hd() |> Map.fetch!(:id)}
  end
end
