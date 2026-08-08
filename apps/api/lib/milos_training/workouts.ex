defmodule MilosTraining.Workouts do
  alias MilosTraining.Workouts.Domain.{WorkoutDsl, WorkoutType}
  alias MilosTraining.Workouts.Domain.WorkoutDsl.Preflight
  alias MilosTraining.Workouts.Domain.WorkoutDsl.{Manual, Templates, Vocabulary}

  alias MilosTraining.Workouts.Commands.{
    ArchiveAthleteAssignments,
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

  alias MilosTraining.Workouts.WorkoutStore

  def create_workout(admin, params), do: CreateWorkout.call(admin.id, params)

  def create_workout(context, admin, params),
    do: WorkoutStore.create_workout(context, admin.id, params)

  def create_draft(admin), do: CreateDraftWorkout.call(admin.id)
  def create_draft(context, admin), do: WorkoutStore.create_draft(context, admin.id)
  defdelegate delete_workout(id), to: DeleteWorkout, as: :call
  defdelegate assign_workout(params), to: AssignWorkout, as: :call
  def assign_workout(context, params), do: WorkoutStore.assign_workout(context, params)
  defdelegate update_assigned_workout(id, params), to: UpdateAssignedWorkout, as: :call

  def update_assigned_workout(context, id, params),
    do: WorkoutStore.update_assigned_workout(context, id, params)

  defdelegate delete_assigned_workout(id), to: DeleteAssignedWorkout, as: :call
  def delete_assigned_workout(context, id), do: WorkoutStore.delete_assigned_workout(context, id)
  def update_draft(id, params), do: UpdateDraftWorkout.call(id, params)
  def publish_workout(id, params), do: PublishWorkout.call(id, params)
  def publish_workout(context, id, params), do: WorkoutStore.publish_workout(context, id, params)
  defdelegate get_workout(id), to: GetWorkout, as: :by_id
  def get_workout(context, id), do: WorkoutStore.get_workout(context, id)
  defdelegate get_workout_for_admin(id), to: GetAdminWorkout, as: :by_id
  def get_workout_for_admin(context, id), do: WorkoutStore.get_workout_for_admin(context, id)
  def exercise_exists?(id), do: MilosTraining.Workouts.WorkoutStore.exercise_exists?(id)

  defdelegate list_assigned_workouts_for_admin(start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_admin

  def list_assigned_workouts_for_admin(context, start_date, end_date),
    do: WorkoutStore.list_assigned_workouts_for_admin(context, start_date, end_date)

  defdelegate list_workout_change_targets(workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_assigned_workouts_for_athlete(athlete_id, start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_athlete

  def list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date),
    do: WorkoutStore.list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date)

  defdelegate list_workouts, to: ListAdminWorkouts, as: :all
  def list_workouts(context), do: WorkoutStore.list_workouts(context)
  defdelegate list_scale_levels, to: ListScaleLevels, as: :all
  defdelegate replace_scale_levels(levels), to: ReplaceScaleLevels, as: :call
  defdelegate materialize_workout(id), to: MaterializeWorkout, as: :by_id
  def supported_workout_types, do: WorkoutType.values()
  def parse_dsl(source), do: WorkoutDsl.parse(source)
  def format_dsl(workout, opts \\ []), do: WorkoutDsl.format(workout, opts)
  def dsl_vocabulary, do: Vocabulary.export()
  def dsl_manual, do: Manual.export()
  def dsl_templates, do: Templates.export()

  def preflight_dsl(workout, active_scale_slugs),
    do: Preflight.validate(workout, active_scale_slugs)

  def reject_assignment_for_athlete(assignment_id, athlete_id),
    do:
      MilosTraining.Workouts.WorkoutStore.reject_assignment_for_athlete(assignment_id, athlete_id)

  defdelegate archive_active_assignments_for_athlete(context, athlete_id),
    to: MilosTraining.Workouts.WorkoutStore,
    as: :archive_active_assignments_for_athlete

  defdelegate archive_active_assignments_for_athlete(athlete_id),
    to: ArchiveAthleteAssignments,
    as: :call

  defdelegate reopen_workout(id), to: ReopenWorkout, as: :call

  def duplicate_workout(id, title_suffix \\ "(copy)", attrs \\ %{}),
    do: DuplicateWorkout.call(id, title_suffix, attrs)

  def duplicate_workout(context, id, title_suffix, attrs),
    do: WorkoutStore.duplicate_workout(context, id, title_suffix, attrs)

  def list_folders, do: MilosTraining.Workouts.WorkoutStore.list_folders()
  def list_folders(context), do: WorkoutStore.list_folders(context)

  def create_folder(admin_id, params),
    do: MilosTraining.Workouts.WorkoutStore.create_folder(admin_id, params)

  def create_folder(context, admin_id, params),
    do: WorkoutStore.create_folder(context, admin_id, params)

  def update_folder(id, params), do: MilosTraining.Workouts.WorkoutStore.update_folder(id, params)
  def update_folder(context, id, params), do: WorkoutStore.update_folder(context, id, params)
  def delete_folder(id), do: MilosTraining.Workouts.WorkoutStore.delete_folder(id)
  def delete_folder(context, id), do: WorkoutStore.delete_folder(context, id)

  def update_library_metadata(id, params),
    do: MilosTraining.Workouts.WorkoutStore.update_library_metadata(id, params)

  def update_library_metadata(context, id, params),
    do: WorkoutStore.update_library_metadata(context, id, params)

  def get_assigned_workout(id), do: MilosTraining.Workouts.WorkoutStore.get_assigned_workout(id)
  def get_assigned_workout(context, id), do: WorkoutStore.get_assigned_workout(context, id)

  def get_assignment_execution_access(assignment_id, athlete_id),
    do:
      MilosTraining.Workouts.WorkoutStore.get_assignment_execution_access(
        assignment_id,
        athlete_id
      )

  defdelegate substitute_assignment_workout(assignment_id, new_workout_id),
    to: SubstituteAssignmentWorkout,
    as: :call

  defdelegate delete_superseded_drafts(published_id, admin_id),
    to: MilosTraining.Workouts.WorkoutStore

  def materialize_workout_for_scale(id, scale_slug) do
    case get_workout(id) do
      nil ->
        nil

      workout ->
        MilosTraining.Workouts.Domain.WorkoutMaterializer.materialize(workout, scale_slug)
    end
  end

  def get_assignment(assignment_id) do
    MilosTraining.Workouts.WorkoutStore.get_assignment(assignment_id)
  end

  def update_assignment_date(id, from_date, new_date) do
    MilosTraining.Workouts.WorkoutStore.update_assignment_date(id, from_date, new_date)
  end
end
