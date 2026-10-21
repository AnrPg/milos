defmodule MilosTraining.Workouts do
  alias MilosTraining.Workouts.Domain.{
    ExerciseDescriptors,
    TimerConfig,
    WorkoutDsl,
    WorkoutFocus,
    WorkoutType
  }

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
    SeedDefaultScaleLevels,
    SubstituteAssignmentWorkout,
    UpdateAssignedWorkout,
    UpdateDraftWorkout
  }

  alias MilosTraining.Workouts.Queries.{
    AnalyzeFreeText,
    GetAdminWorkout,
    ListWorkoutChangeTargets,
    GetWorkout,
    GetAthleteWeekView,
    ListAdminWorkouts,
    ListClassVariants,
    ListScaleLevels,
    MaterializeWorkout
  }

  alias MilosTraining.Workouts.{GoalStore, WorkoutStore}

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: WorkoutStore.with_tenant_context(context, fun)

  def create_workout(admin, params), do: CreateWorkout.call(admin.id, params)

  def create_workout(context, admin, params),
    do: WorkoutStore.create_workout(context, admin.id, params)

  @doc "Proposes a canonical reading of a free-text workout. Never persists."
  def analyze_free_text(text, options), do: AnalyzeFreeText.call(text, options)

  def create_draft(admin), do: CreateDraftWorkout.call(admin.id)
  def create_draft(context, admin), do: WorkoutStore.create_draft(context, admin.id)
  defdelegate delete_workout(id), to: DeleteWorkout, as: :call
  def delete_workout(context, id), do: WorkoutStore.delete_workout(context, id)
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
  # Every read takes a tenant context (ADR-091, ADR-133): the store opens that
  # tenant's RepoContext session, so a read never depends on whatever session
  # the caller happened to have open.
  defdelegate get_workout(context, id), to: GetWorkout, as: :by_id
  defdelegate get_workout_for_admin(context, id), to: GetAdminWorkout, as: :by_id
  def exercise_exists?(context, id), do: WorkoutStore.exercise_exists?(context, id)

  defdelegate list_assigned_workouts_for_admin(context, start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_admin

  defdelegate list_workout_change_targets(context, workout_id),
    to: ListWorkoutChangeTargets,
    as: :for_workout

  defdelegate list_assigned_workouts_for_athlete(context, athlete_id, start_date, end_date),
    to: GetAthleteWeekView,
    as: :for_athlete

  @doc "ADR-125: live per-member class variants for slots (one assignee or all)."
  def list_class_variants(context, slot_ids, assignee_id),
    do: ListClassVariants.call(context, slot_ids, assignee_id)

  defdelegate list_workouts(context), to: ListAdminWorkouts, as: :all
  defdelegate list_scale_levels(context), to: ListScaleLevels, as: :all
  defdelegate replace_scale_levels(context, levels), to: ReplaceScaleLevels, as: :call
  defdelegate seed_default_scale_levels(context), to: SeedDefaultScaleLevels, as: :call

  @doc "`%{workout, scales}` with every scale materialized, or nil."
  defdelegate materialize_workout(context, id), to: MaterializeWorkout, as: :by_id

  @doc "The workout materialized for one scale, or nil."
  defdelegate materialize_workout_for_scale(context, id, scale_slug),
    to: MaterializeWorkout,
    as: :for_scale

  def supported_workout_types, do: WorkoutType.values()
  def parse_dsl(source), do: WorkoutDsl.parse(source)
  def normalize_timer_config(config), do: TimerConfig.normalize(config)
  def format_dsl(workout, opts \\ []), do: WorkoutDsl.format(workout, opts)
  def dsl_vocabulary, do: Vocabulary.export()
  def dsl_manual, do: Manual.export()
  def dsl_templates, do: Templates.export()

  def preflight_dsl(workout, active_scale_slugs),
    do: Preflight.validate(workout, active_scale_slugs)

  @doc "`%{name, exercise_ref, category}` per exercise of a normalized workout (ADR-124)."
  def exercise_descriptors(workout), do: ExerciseDescriptors.from_workout(workout)

  @doc """
  `%{name, exercise_ref, category, weight}` per exercise of a workout, for
  WOD-goal suggestion (ADR-163): sections when it has them, else its free
  text read line by line.
  """
  def goal_exercises(workout), do: ExerciseDescriptors.weighted_from_workout(workout)

  @doc """
  The Quick Text catalog entry (`%{id, label, category}`) an exercise names:
  its `exercise_ref` when known, else its name read leniently (plurals),
  else nil (ADR-164: performed exercises of log entries, tagged videos).
  """
  def resolve_catalog_exercise(exercise_ref, name),
    do: ExerciseDescriptors.resolve_catalog_entry(exercise_ref, name)

  @doc "The saved WOD goals of a workout in the context's gym, or nil (ADR-163)."
  def get_workout_goals(context, workout_id), do: GoalStore.get_goals(context, workout_id)

  @doc """
  The WOD goals a workout uses (ADR-163): its own, else those of the nearest
  workout it was copied from (`source_workout_id`: class variants, member
  versions, filed copies), as `%{goals, inherited_from}`.
  """
  def resolve_workout_goals(context, workout_id),
    do: GoalStore.resolve_goals(context, workout_id)

  @doc "Upserts a workout's WOD goals; attrs are already normalised (ADR-163)."
  def put_workout_goals(context, workout_id, attrs),
    do: GoalStore.put_goals(context, workout_id, attrs)

  @doc "What a workout trains, read from its movements (Πρόγραμμα «Εστίαση» filter)."
  def workout_focus(workout), do: WorkoutFocus.from_workout(workout)

  @doc """
  Descriptors of the exercises an athlete runs at `scale_slug` (TD-088): the
  tenant-fetched workout is materialized for the scale first, so excluded
  exercises drop out and substituted movements are matched by their own name.
  A blank scale means the Rx workout.
  """
  def exercise_descriptors(workout, scale_slug) when scale_slug in [nil, ""],
    do: exercise_descriptors(workout)

  def exercise_descriptors(workout, scale_slug) when is_binary(scale_slug),
    do: workout |> materialize_for_scale(scale_slug) |> exercise_descriptors()

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

  def list_folders(context), do: WorkoutStore.list_folders(context)

  def create_folder(admin_id, params),
    do: MilosTraining.Workouts.WorkoutStore.create_folder(admin_id, params)

  def create_folder(context, admin_id, params),
    do: WorkoutStore.create_folder(context, admin_id, params)

  def update_folder(id, params), do: MilosTraining.Workouts.WorkoutStore.update_folder(id, params)
  def update_folder(context, id, params), do: WorkoutStore.update_folder(context, id, params)

  def set_workout_icon(context, id, icon, icon_source),
    do: WorkoutStore.set_workout_icon(context, id, icon, icon_source)

  def find_filed_copy(context, source_id, folder_id),
    do: WorkoutStore.find_filed_copy(context, source_id, folder_id)

  def ensure_system_folder(context, system_key, name, parent_id),
    do: WorkoutStore.ensure_system_folder(context, system_key, name, parent_id)

  def delete_folder(id), do: MilosTraining.Workouts.WorkoutStore.delete_folder(id)
  def delete_folder(context, id), do: WorkoutStore.delete_folder(context, id)

  def update_library_metadata(id, params),
    do: MilosTraining.Workouts.WorkoutStore.update_library_metadata(id, params)

  def update_library_metadata(context, id, params),
    do: WorkoutStore.update_library_metadata(context, id, params)

  def get_assigned_workout(context, id), do: WorkoutStore.get_assigned_workout(context, id)

  @doc "`{:ok, assignment}` with its athlete links, or `{:error, :not_found}`."
  def get_assignment(context, assignment_id),
    do: WorkoutStore.get_assignment(context, assignment_id)

  def get_assignment_execution_access(context, assignment_id, athlete_id),
    do: WorkoutStore.get_assignment_execution_access(context, assignment_id, athlete_id)

  def substitute_assignment_workout(context, assignment_id, new_workout_id),
    do: WorkoutStore.substitute_assignment_workout(context, assignment_id, new_workout_id)

  defdelegate substitute_assignment_workout(assignment_id, new_workout_id),
    to: SubstituteAssignmentWorkout,
    as: :call

  def delete_superseded_drafts(context, published_id, admin_id),
    do: WorkoutStore.delete_superseded_drafts(context, published_id, admin_id)

  defdelegate delete_superseded_drafts(published_id, admin_id),
    to: MilosTraining.Workouts.WorkoutStore

  # Materializes an already tenant-fetched workout. Scale levels come from the
  # workout's own variations, so they are always the workout's organization's
  # set (ADR-128).
  def materialize_for_scale(workout, scale_slug),
    do: MilosTraining.Workouts.Domain.WorkoutMaterializer.materialize(workout, scale_slug)

  def update_assignment_date(id, from_date, new_date) do
    MilosTraining.Workouts.WorkoutStore.update_assignment_date(id, from_date, new_date)
  end

  def update_assignment_date(context, id, from_date, new_date) do
    MilosTraining.Workouts.WorkoutStore.update_assignment_date(
      context,
      id,
      from_date,
      new_date
    )
  end

  # ADR-117 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Workouts.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
