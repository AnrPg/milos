defmodule MilosTraining.Workouts do
  alias MilosTraining.Workouts.Commands.{
    CreateDraftWorkout,
    CreateWorkout,
    PublishWorkout,
    ReplaceScaleLevels,
    UpdateDraftWorkout
  }

  alias MilosTraining.Workouts.Queries.{
    GetWorkout,
    ListScaleLevels,
    ListWorkouts,
    MaterializeWorkout
  }

  alias MilosTraining.Workouts.WorkoutStore

  def create_workout(admin, params), do: CreateWorkout.call(admin.id, params)
  def create_draft(admin), do: CreateDraftWorkout.call(admin.id)
  def update_draft(id, params), do: UpdateDraftWorkout.call(id, params)
  def publish_workout(id, params), do: PublishWorkout.call(id, params)
  defdelegate get_workout(id), to: GetWorkout, as: :by_id
  def get_workout_for_admin(id), do: WorkoutStore.get_workout_for_admin(id)
  defdelegate list_workouts, to: ListWorkouts, as: :all
  defdelegate list_scale_levels, to: ListScaleLevels, as: :all
  defdelegate replace_scale_levels(levels), to: ReplaceScaleLevels, as: :call
  defdelegate materialize_workout(id), to: MaterializeWorkout, as: :by_id
end
