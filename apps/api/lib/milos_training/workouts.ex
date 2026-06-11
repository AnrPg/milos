defmodule MilosTraining.Workouts do
  alias MilosTraining.Workouts.Commands.{
    AssignWorkout,
    CreateDraftWorkout,
    CreateWorkout,
    DeleteAssignedWorkout,
    DeleteWorkout,
    DuplicateWorkout,
    PublishWorkout,
    ReplaceScaleLevels,
    ReopenWorkout,
    SubstituteAssignmentWorkout,
    UpdateAssignedWorkout,
    UpdateDraftWorkout
  }

  alias MilosTraining.Workouts.Queries.{
    GetAdminWorkout,
    ListWorkoutChangeTargets,
    GetWorkout,
    GetAthleteWeekView,
    ListAdminWorkouts,
    ListScaleLevels,
    MaterializeWorkout
  }

  def create_workout(admin, params), do: CreateWorkout.call(admin.id, params)
  def create_draft(admin), do: CreateDraftWorkout.call(admin.id)
  defdelegate delete_workout(id), to: DeleteWorkout, as: :call
  defdelegate assign_workout(params), to: AssignWorkout, as: :call
  defdelegate update_assigned_workout(id, params), to: UpdateAssignedWorkout, as: :call
  defdelegate delete_assigned_workout(id), to: DeleteAssignedWorkout, as: :call
  def update_draft(id, params), do: UpdateDraftWorkout.call(id, params)
  def publish_workout(id, params), do: PublishWorkout.call(id, params)
  defdelegate get_workout(id), to: GetWorkout, as: :by_id
  defdelegate get_workout_for_admin(id), to: GetAdminWorkout, as: :by_id

  defdelegate list_assigned_workouts_for_admin(start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_admin

  defdelegate list_workout_change_targets(workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_assigned_workouts_for_athlete(athlete_id, start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_athlete

  defdelegate list_workouts, to: ListAdminWorkouts, as: :all
  defdelegate list_scale_levels, to: ListScaleLevels, as: :all
  defdelegate replace_scale_levels(levels), to: ReplaceScaleLevels, as: :call
  defdelegate materialize_workout(id), to: MaterializeWorkout, as: :by_id

  def reject_assignment_for_athlete(assignment_id, athlete_id),
    do:
      MilosTraining.Workouts.WorkoutStore.reject_assignment_for_athlete(assignment_id, athlete_id)

  defdelegate reopen_workout(id), to: ReopenWorkout, as: :call
  def duplicate_workout(id, title_suffix \\ "(copy)"), do: DuplicateWorkout.call(id, title_suffix)
  def get_assigned_workout(id), do: MilosTraining.Workouts.WorkoutStore.get_assigned_workout(id)

  defdelegate substitute_assignment_workout(assignment_id, new_workout_id),
    to: SubstituteAssignmentWorkout,
    as: :call

  def materialize_workout_for_scale(id, scale_slug) do
    case get_workout(id) do
      nil ->
        nil

      workout ->
        MilosTraining.Workouts.Domain.WorkoutMaterializer.materialize(workout, scale_slug)
    end
  end

  def get_assignment_with_auth(assignment_id, actor) do
    MilosTraining.Workouts.WorkoutStore.get_assignment_with_auth(assignment_id, actor)
  end

  def list_assignment_messages(assignment_id) do
    MilosTraining.Workouts.WorkoutStore.list_assignment_messages(assignment_id)
  end

  def create_assignment_message(params) do
    MilosTraining.Workouts.WorkoutStore.create_assignment_message(params)
  end

  def update_assignment_date(id, from_date, new_date) do
    MilosTraining.Workouts.WorkoutStore.update_assignment_date(id, from_date, new_date)
  end
end
