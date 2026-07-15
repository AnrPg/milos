defmodule MilosTraining.Infrastructure.Coaching.EctoCoachingStore do
  @behaviour MilosTraining.Coaching.Ports.CoachingStore

  alias MilosTraining.Repo

  @impl true
  def get_aggregates do
    case Repo.query("""
         SELECT period_start, active_athlete_count, inactive_athlete_count,
                completed_workouts_this_week, coach_notes_this_week,
                average_completion_rate, recent_workout_note_count
         FROM coaching_aggregates
         ORDER BY period_start DESC
         LIMIT 1
         """) do
      {:ok, %{rows: [[period_start, active, inactive, completed, notes, rate, recent_notes]]}} ->
        %{
          period_start: period_start,
          active_athlete_count: active,
          inactive_athlete_count: inactive,
          completed_workouts_this_week: completed,
          coach_notes_this_week: notes,
          average_completion_rate: rate,
          recent_workout_note_count: recent_notes,
          aggregate_status: "available"
        }

      {:ok, %{rows: []}} ->
        empty_aggregates("available", nil)

      {:error, reason} ->
        empty_aggregates("unavailable", inspect(reason))
    end
  end

  @impl true
  def refresh_aggregates do
    case Repo.query("REFRESH MATERIALIZED VIEW coaching_aggregates") do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp empty_aggregates(status, error) do
    %{
      period_start: nil,
      active_athlete_count: 0,
      inactive_athlete_count: 0,
      completed_workouts_this_week: 0,
      coach_notes_this_week: 0,
      average_completion_rate: 0.0,
      recent_workout_note_count: 0,
      aggregate_status: status,
      aggregate_error: error
    }
  end
end
