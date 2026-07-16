defmodule MilosTraining.Workouts.WorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  defp adapter do
    Application.fetch_env!(:milos_training, :workout_store)
  end

  @impl true
  def create_workout(admin_id, params), do: adapter().create_workout(admin_id, params)

  @impl true
  def create_draft(admin_id), do: adapter().create_draft(admin_id)

  @impl true
  def update_draft(id, params), do: adapter().update_draft(id, params)

  @impl true
  def delete_workout(id), do: adapter().delete_workout(id)

  @impl true
  def publish_workout(id, params), do: adapter().publish_workout(id, params)

  @impl true
  def get_workout(id), do: adapter().get_workout(id)

  @impl true
  def get_workout_for_admin(id), do: adapter().get_workout_for_admin(id)

  @impl true
  def exercise_exists?(id), do: adapter().exercise_exists?(id)

  @impl true
  def assign_workout(params), do: adapter().assign_workout(params)

  @impl true
  def update_assigned_workout(id, params), do: adapter().update_assigned_workout(id, params)

  @impl true
  def delete_assigned_workout(id), do: adapter().delete_assigned_workout(id)

  @impl true
  def list_assigned_workouts_for_athlete(athlete_id, start_date, end_date),
    do: adapter().list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)

  @impl true
  def list_workout_change_targets(workout_id),
    do: adapter().list_workout_change_targets(workout_id)

  @impl true
  def list_assigned_workouts_for_admin(start_date, end_date),
    do: adapter().list_assigned_workouts_for_admin(start_date, end_date)

  @impl true
  def list_workouts, do: adapter().list_workouts()

  @impl true
  def list_scale_levels, do: adapter().list_scale_levels()

  @impl true
  def replace_scale_levels(levels), do: adapter().replace_scale_levels(levels)

  @impl true
  def reject_assignment_for_athlete(assignment_id, athlete_id),
    do: adapter().reject_assignment_for_athlete(assignment_id, athlete_id)

  @impl true
  def archive_active_assignments_for_athlete(athlete_id),
    do: adapter().archive_active_assignments_for_athlete(athlete_id)

  @impl true
  def reopen_workout(id), do: adapter().reopen_workout(id)

  @impl true
  def get_assigned_workout(id), do: adapter().get_assigned_workout(id)

  @impl true
  def get_assignment_execution_access(assignment_id, athlete_id),
    do: adapter().get_assignment_execution_access(assignment_id, athlete_id)

  @impl true
  def duplicate_workout(id, title_suffix), do: adapter().duplicate_workout(id, title_suffix)

  @impl true
  def substitute_assignment_workout(assignment_id, new_workout_id),
    do: adapter().substitute_assignment_workout(assignment_id, new_workout_id)

  @impl true
  def get_assignment_with_auth(assignment_id, actor),
    do: adapter().get_assignment_with_auth(assignment_id, actor)

  @impl true
  def update_assignment_date(id, athlete_id, new_date),
    do: adapter().update_assignment_date(id, athlete_id, new_date)

  @impl true
  def delete_superseded_drafts(published_id, admin_id),
    do: adapter().delete_superseded_drafts(published_id, admin_id)
end
