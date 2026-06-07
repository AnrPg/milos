defmodule MilosTraining.Workouts.WorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  defp adapter do
    Application.get_env(
      :milos_training,
      :workout_store,
      MilosTraining.Infrastructure.Workouts.EctoWorkoutStore
    )
  end

  @impl true
  def create_workout(admin_id, params), do: adapter().create_workout(admin_id, params)

  @impl true
  def create_draft(admin_id), do: adapter().create_draft(admin_id)

  @impl true
  def update_draft(id, params), do: adapter().update_draft(id, params)

  @impl true
  def publish_workout(id, params), do: adapter().publish_workout(id, params)

  @impl true
  def get_workout(id), do: adapter().get_workout(id)

  @impl true
  def get_workout_for_admin(id), do: adapter().get_workout_for_admin(id)

  @impl true
  def list_workouts, do: adapter().list_workouts()

  @impl true
  def list_scale_levels, do: adapter().list_scale_levels()

  @impl true
  def replace_scale_levels(levels), do: adapter().replace_scale_levels(levels)
end
