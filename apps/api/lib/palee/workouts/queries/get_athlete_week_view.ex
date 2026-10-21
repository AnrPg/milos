defmodule Palee.Workouts.Queries.GetAthleteWeekView do
  alias Palee.Workouts.WorkoutStore

  def for_athlete(context, athlete_id, start_date, end_date),
    do: WorkoutStore.list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date)

  def for_admin(context, start_date, end_date),
    do: WorkoutStore.list_assigned_workouts_for_admin(context, start_date, end_date)
end
