defmodule MilosTraining.Workouts.Queries.GetAthleteWeekView do
  alias MilosTraining.Workouts.WorkoutStore

  def for_athlete(athlete_id, start_date, end_date) do
    WorkoutStore.list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)
  end

  def for_admin(start_date, end_date) do
    WorkoutStore.list_assigned_workouts_for_admin(start_date, end_date)
  end
end
