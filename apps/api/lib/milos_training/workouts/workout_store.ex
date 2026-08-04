defmodule MilosTraining.Workouts.WorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter do
    Application.fetch_env!(:milos_training, :workout_store)
  end

  # Scoped variants are the tenant-aware public boundary. The legacy arities remain
  # temporarily for jobs and callers still being migrated; RLS limits those to legacy.
  def create_draft(context, admin_id),
    do: within_tenant(context, fn -> create_draft(admin_id) end)

  def create_workout(context, admin_id, params),
    do: within_tenant(context, fn -> create_workout(admin_id, params) end)

  def update_draft(context, id, params),
    do: within_tenant(context, fn -> update_draft(id, params) end)

  def delete_workout(context, id), do: within_tenant(context, fn -> delete_workout(id) end)

  def publish_workout(context, id, params),
    do: within_tenant(context, fn -> publish_workout(id, params) end)

  def get_workout(context, id), do: within_tenant(context, fn -> get_workout(id) end)

  def get_workout_for_admin(context, id),
    do: within_tenant(context, fn -> get_workout_for_admin(id) end)

  def list_workouts(context), do: within_tenant(context, &list_workouts/0)
  def list_folders(context), do: within_tenant(context, &list_folders/0)

  def create_folder(context, admin_id, params),
    do: within_tenant(context, fn -> create_folder(admin_id, params) end)

  def update_folder(context, id, params),
    do: within_tenant(context, fn -> update_folder(id, params) end)

  def delete_folder(context, id), do: within_tenant(context, fn -> delete_folder(id) end)

  def update_library_metadata(context, id, params),
    do: within_tenant(context, fn -> update_library_metadata(id, params) end)

  def assign_workout(context, params),
    do: within_tenant(context, fn -> assign_workout(params) end)

  def update_assigned_workout(context, id, params),
    do: within_tenant(context, fn -> update_assigned_workout(id, params) end)

  def delete_assigned_workout(context, id),
    do: within_tenant(context, fn -> delete_assigned_workout(id) end)

  def get_assigned_workout(context, id),
    do: within_tenant(context, fn -> get_assigned_workout(id) end)

  def list_assigned_workouts_for_admin(context, start_date, end_date),
    do: within_tenant(context, fn -> list_assigned_workouts_for_admin(start_date, end_date) end)

  def list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date),
    do:
      within_tenant(context, fn ->
        list_assigned_workouts_for_athlete(athlete_id, start_date, end_date)
      end)

  def reject_assignment_for_athlete(context, assignment_id, athlete_id),
    do: within_tenant(context, fn -> reject_assignment_for_athlete(assignment_id, athlete_id) end)

  def reopen_workout(context, id), do: within_tenant(context, fn -> reopen_workout(id) end)

  def duplicate_workout(context, id, title_suffix, attrs),
    do: within_tenant(context, fn -> duplicate_workout(id, title_suffix, attrs) end)

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
  def list_folders, do: adapter().list_folders()

  @impl true
  def create_folder(admin_id, params), do: adapter().create_folder(admin_id, params)

  @impl true
  def update_folder(id, params), do: adapter().update_folder(id, params)

  @impl true
  def delete_folder(id), do: adapter().delete_folder(id)

  @impl true
  def update_library_metadata(id, params), do: adapter().update_library_metadata(id, params)

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
  def duplicate_workout(id, title_suffix, attrs \\ %{}),
    do: adapter().duplicate_workout(id, title_suffix, attrs)

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

  defp within_tenant(context, fun), do: RepoContext.run(context, fun)
end
