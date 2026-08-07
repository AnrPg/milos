defmodule MilosTraining.Infrastructure.Workouts.EctoWorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  import Ecto.Query

  alias Ecto.Multi

  alias MilosTraining.{
    Execution.WorkoutExecution,
    Infrastructure.Tenancy.RepoContext,
    Repo,
    ScaleLevel,
    Workouts.AssignedWorkout,
    Workouts.AssignedWorkoutAthlete,
    Workouts.Domain.WorkoutAuthoring,
    Workouts.Domain.WorkoutMaterializer,
    Workouts.ExerciseVariation,
    Workouts.MasterWorkout,
    Workouts.WorkoutFolder,
    Workouts.WorkoutExercise,
    Workouts.WorkoutSection
  }

  @workout_preloads [sections: [exercises: [variations: [:scale_level]]]]
  @assigned_workout_preloads [:athlete_links, master_workout: @workout_preloads]

  @impl true
  def create_workout(admin_id, params) do
    with {:ok, normalized_params} <- prepare_workout_structure(params),
         {:ok, params_with_levels} <- attach_scale_level_ids(normalized_params) do
      params_with_levels
      |> Map.put(:created_by_id, admin_id)
      |> then(&MasterWorkout.create_changeset(%MasterWorkout{}, &1))
      |> Repo.insert()
      |> case do
        {:ok, workout} ->
          workout =
            workout
            |> Repo.preload(@workout_preloads)
            |> normalize_workout(note_visibility: :admin)

          {:ok, workout}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}
      end
    end
  end

  @impl true
  def create_draft(admin_id) do
    %MasterWorkout{}
    |> MasterWorkout.draft_changeset(%{created_by_id: admin_id, status: :draft})
    |> Repo.insert()
    |> case do
      {:ok, workout} ->
        {:ok,
         %{
           id: workout.id,
           status: to_string(workout.status),
           authoring_mode: workout.authoring_mode,
           dsl_source_revision: workout.dsl_source_revision
         }}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:error, changeset}
    end
  end

  @impl true
  def update_draft(id, params) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      workout ->
        with :ok <- validate_expected_revision(workout, params) do
          draft_data =
            params
            |> Map.get(:draft_data, Map.get(params, "draft_data", params))
            |> stringify_keys_deep()

          top_level =
            draft_data
            |> extract_top_level_draft_fields()
            |> Map.merge(extract_dsl_authoring_fields(params))
            |> Map.put(:draft_data, draft_data)

          changeset =
            workout
            |> MasterWorkout.update_draft_changeset(top_level)
            |> maybe_lock_dsl_revision(params)

          try do
            case Repo.update(changeset) do
              {:ok, updated} -> {:ok, draft_summary(updated)}
              {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
            end
          rescue
            Ecto.StaleEntryError -> {:error, :stale_dsl_revision}
          end
        end
    end
  end

  @impl true
  def delete_workout(id) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %MasterWorkout{} = workout ->
        case Repo.delete(workout) do
          {:ok, _deleted_workout} -> :ok
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def publish_workout(id, params) do
    result =
      Repo.transaction(fn ->
        workout =
          MasterWorkout
          |> where([workout], workout.id == ^id)
          |> lock("FOR UPDATE")
          |> Repo.one()

        case publish_locked_workout(workout, params) do
          {:ok, published} -> published
          {:error, reason} -> Repo.rollback(reason)
        end
      end)

    case result do
      {:ok, published} ->
        published =
          published
          |> Repo.preload(@workout_preloads)
          |> normalize_workout(note_visibility: :admin)
          |> Map.merge(authoring_state(published))

        {:ok, published}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def workout_organization_id(id) do
    # Deliberately un-scoped: this exists to *derive* the tenant for a workout
    # execution (F-03), so it cannot itself require a tenant already be open.
    # It exposes only which organization owns a workout id, and every caller
    # must follow it with a membership check.
    MasterWorkout
    |> where([workout], workout.id == ^id)
    |> select([workout], workout.organization_id)
    |> Repo.one()
  end

  @impl true
  def get_workout(id) do
    MasterWorkout
    |> scoped_to_tenant()
    |> Repo.get(id)
    |> case do
      nil ->
        nil

      %MasterWorkout{status: :published} = workout ->
        workout
        |> Repo.preload(@workout_preloads)
        |> normalize_workout()

      %MasterWorkout{} ->
        nil
    end
  end

  @impl true
  def get_workout_for_admin(id) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        nil

      %MasterWorkout{} = workout ->
        draft_sections =
          workout.draft_data
          |> extract_sections_from_draft()

        base = %{
          id: workout.id,
          title: workout.title,
          subtitle: workout.subtitle,
          description: workout.description,
          type: workout.type && to_string(workout.type),
          status: to_string(workout.status),
          is_team_workout: workout.is_team_workout,
          difficulty: workout.difficulty,
          estimated_duration_seconds: workout.estimated_duration_seconds,
          equipment: workout.equipment,
          tags: workout.tags,
          notes: workout.notes,
          workout_metadata: workout.workout_metadata,
          authoring_mode: workout.authoring_mode,
          dsl_version: workout.dsl_version,
          dsl_source: workout.dsl_source,
          dsl_document: workout.dsl_document,
          dsl_source_revision: workout.dsl_source_revision,
          last_dsl_diagnostics: workout.last_dsl_diagnostics,
          free_text_body: workout.free_text_body,
          free_text_document: workout.free_text_document,
          draft_data: workout.draft_data,
          sections: draft_sections
        }

        if workout.status == :published do
          workout
          |> Repo.preload(@workout_preloads)
          |> normalize_workout(note_visibility: :admin)
          |> Map.put(:draft_data, workout.draft_data)
          |> Map.merge(authoring_state(workout))
        else
          base
        end
    end
  end

  @impl true
  def exercise_exists?(id) do
    WorkoutExercise
    |> where([exercise], exercise.id == ^id)
    |> Repo.exists?()
  end

  @impl true
  def list_workouts do
    MasterWorkout
    |> scoped_to_tenant()
    |> order_by([workout], desc: workout.inserted_at)
    |> Repo.all()
    |> Repo.preload(@workout_preloads)
    |> Enum.map(fn workout ->
      workout
      |> normalize_workout(note_visibility: :admin)
      |> Map.update!(:sections, &summarize_sections_for_list/1)
    end)
  end

  @impl true
  def list_folders do
    WorkoutFolder
    |> order_by([folder], asc: folder.name)
    |> Repo.all()
    |> Enum.map(&normalize_folder/1)
  end

  @impl true
  def create_folder(admin_id, params) do
    key = if Enum.any?(Map.keys(params), &is_binary/1), do: "created_by_id", else: :created_by_id
    params = Map.put(params, key, admin_id)

    with :ok <- validate_folder_parent(nil, params),
         {:ok, folder} <- %WorkoutFolder{} |> WorkoutFolder.changeset(params) |> Repo.insert() do
      {:ok, normalize_folder(folder)}
    end
  end

  @impl true
  def update_folder(id, params) do
    case WorkoutFolder |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      folder ->
        with :ok <- validate_folder_parent(folder, params),
             {:ok, updated} <- folder |> WorkoutFolder.changeset(params) |> Repo.update() do
          {:ok, normalize_folder(updated)}
        end
    end
  end

  @impl true
  def delete_folder(id) do
    case WorkoutFolder |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      folder ->
        Repo.transaction(fn ->
          from(child in WorkoutFolder, where: child.parent_id == ^id)
          |> Repo.update_all(set: [parent_id: folder.parent_id])

          from(workout in MasterWorkout, where: workout.folder_id == ^id)
          |> Repo.update_all(set: [folder_id: folder.parent_id])

          Repo.delete!(folder)
        end)
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @impl true
  def update_library_metadata(id, params) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      workout ->
        workout
        |> Ecto.Changeset.cast(params, [:folder_id, :source_workout_id])
        |> Ecto.Changeset.foreign_key_constraint(:folder_id)
        |> Ecto.Changeset.foreign_key_constraint(:source_workout_id)
        |> Repo.update()
        |> case do
          {:ok, updated} ->
            {:ok,
             %{
               id: updated.id,
               folder_id: updated.folder_id,
               source_workout_id: updated.source_workout_id
             }}

          error ->
            error
        end
    end
  end

  defp summarize_sections_for_list(sections) do
    Enum.map(sections, fn section ->
      %{
        name: section.name,
        order: section.order,
        exercises: List.duplicate(%{}, length(section.exercises))
      }
    end)
  end

  @impl true
  def list_scale_levels do
    ScaleLevel
    |> where([scale_level], scale_level.is_active == true)
    |> order_by([scale_level], asc: scale_level.sort_order)
    |> Repo.all()
    |> Enum.map(&normalize_scale_level/1)
  end

  @impl true
  def replace_scale_levels(levels) when is_list(levels) do
    cleaned_levels =
      levels
      |> Enum.map(&normalize_scale_level_params/1)
      |> Enum.reject(&blank_scale_level?/1)

    changeset =
      Ecto.Changeset.change(%ScaleLevel{})
      |> validate_scale_level_list(cleaned_levels)

    if changeset.valid? do
      do_replace_scale_levels(cleaned_levels)
    else
      {:error, changeset}
    end
  end

  @impl true
  def assign_workout(params) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> Enum.uniq()

    workout_id = Map.get(params, :master_workout_id) || Map.get(params, "master_workout_id")
    scheduled_for = Map.get(params, :scheduled_for) || Map.get(params, "scheduled_for")
    admin_notes = normalize_admin_notes_input(params)

    case find_assignment_by_workout_date_and_notes(workout_id, scheduled_for, admin_notes) do
      nil ->
        %AssignedWorkout{}
        |> AssignedWorkout.changeset(params)
        |> validate_assignment_athletes(athlete_ids)
        |> persist_assigned_workout(athlete_ids)

      %AssignedWorkout{} = assignment ->
        merged_athlete_ids = (existing_athlete_ids(assignment) ++ athlete_ids) |> Enum.uniq()

        assignment
        |> AssignedWorkout.update_changeset(params)
        |> validate_assignment_athletes(merged_athlete_ids)
        |> persist_assigned_workout(merged_athlete_ids)
    end
  end

  @impl true
  def update_assigned_workout(id, params) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> Enum.uniq()

    case AssignedWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %AssignedWorkout{} = assignment ->
        scheduled_for = Map.get(params, :scheduled_for) || Map.get(params, "scheduled_for")
        admin_notes = normalize_admin_notes_input(params)

        case find_conflicting_assignment(
               assignment.master_workout_id,
               scheduled_for,
               admin_notes,
               assignment.id
             ) do
          nil ->
            assignment
            |> AssignedWorkout.update_changeset(params)
            |> validate_assignment_athletes(athlete_ids)
            |> persist_assigned_workout(athlete_ids)

          %AssignedWorkout{} = conflicting_assignment ->
            assignment
            |> AssignedWorkout.update_changeset(params)
            |> validate_assignment_athletes(athlete_ids)
            |> consolidate_assigned_workouts(conflicting_assignment, athlete_ids)
        end
    end
  end

  @impl true
  def delete_assigned_workout(id) do
    case AssignedWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %AssignedWorkout{} = assignment ->
        case Repo.delete(assignment) do
          {:ok, _assignment} -> :ok
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def list_assigned_workouts_for_athlete(athlete_id, start_date, end_date) do
    normalized =
      AssignedWorkout
      |> join(:inner, [assignment], link in AssignedWorkoutAthlete,
        on: link.assigned_workout_id == assignment.id
      )
      |> where(
        [assignment, link],
        link.athlete_id == ^athlete_id and
          (is_nil(link.athlete_status) or link.athlete_status != :archived) and
          link.scheduled_for >= ^start_date and
          link.scheduled_for <= ^end_date
      )
      |> order_by([assignment, link], asc: link.scheduled_for, asc: assignment.inserted_at)
      |> Repo.all()
      |> Repo.preload(@assigned_workout_preloads)
      |> Enum.map(&normalize_assignment_for_athlete(&1, athlete_id))

    assignment_ids = Enum.map(normalized, & &1.id)
    completion_map = fetch_completed_assignment_executions(athlete_id, assignment_ids)

    Enum.map(normalized, fn assignment ->
      case Map.get(completion_map, assignment.id) do
        nil ->
          assignment

        execution ->
          Map.merge(assignment, %{
            execution_status: "completed",
            execution_scores: execution.section_scores || []
          })
      end
    end)
  end

  @impl true
  def list_assigned_workouts_for_admin(start_date, end_date) do
    AssignedWorkout
    |> where(
      [assignment],
      assignment.scheduled_for >= ^start_date and assignment.scheduled_for <= ^end_date
    )
    |> order_by([assignment], asc: assignment.scheduled_for, asc: assignment.inserted_at)
    |> Repo.all()
    |> Repo.preload(@assigned_workout_preloads)
    |> Enum.map(&normalize_assignment/1)
  end

  @impl true
  def list_workout_change_targets(workout_id) do
    AssignedWorkout
    |> where([assignment], assignment.master_workout_id == ^workout_id)
    |> Repo.all()
    |> Repo.preload(:athlete_links)
    |> Enum.flat_map(fn assignment ->
      assignment.athlete_links
      |> Enum.reject(&(&1.athlete_status == :archived))
      |> Enum.map(fn link ->
        %{
          user_id: link.athlete_id,
          scheduled_for: assignment.scheduled_for,
          assigned_workout_id: assignment.id
        }
      end)
    end)
  end

  @impl true
  def archive_active_assignments_for_athlete(%{organization_id: organization_id}, athlete_id) do
    archive_active_assignments(athlete_id, organization_id)
  end

  @impl true
  def archive_active_assignments_for_athlete(athlete_id) do
    # Legacy un-scoped arity (F-18): reaches every organization's assignments.
    archive_active_assignments(athlete_id, nil)
  end

  defp scope_links_to_organization(query, nil), do: query

  defp scope_links_to_organization(query, organization_id),
    do: where(query, [link], link.organization_id == ^organization_id)

  defp archive_active_assignments(athlete_id, organization_id) do
    Repo.transaction(fn ->
      links =
        AssignedWorkoutAthlete
        |> where(
          [link],
          link.athlete_id == ^athlete_id and
            (is_nil(link.athlete_status) or link.athlete_status == :accepted)
        )
        |> scope_links_to_organization(organization_id)
        |> order_by([link], asc: link.id)
        |> lock("FOR UPDATE")
        |> Repo.all()

      Enum.reduce_while(links, [], fn link, assignment_ids ->
        case link |> AssignedWorkoutAthlete.archive_changeset() |> Repo.update() do
          {:ok, archived} -> {:cont, [archived.assigned_workout_id | assignment_ids]}
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)
      |> Enum.uniq()
      |> Enum.reverse()
    end)
  end

  defp do_replace_scale_levels(levels) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Multi.new()
    |> Multi.run(:existing, fn repo, _changes ->
      {:ok, repo.all(from(scale_level in ScaleLevel))}
    end)
    |> Multi.run(:guard_removals, fn repo, %{existing: existing} ->
      requested_slugs = MapSet.new(Enum.map(levels, & &1.slug))
      removable = Enum.reject(existing, &MapSet.member?(requested_slugs, &1.slug))

      removable_ids = Enum.map(removable, & &1.id)

      count =
        if removable_ids == [] do
          0
        else
          repo.aggregate(
            from(variation in ExerciseVariation,
              where: variation.scale_level_id in ^removable_ids
            ),
            :count
          )
        end

      if count > 0 do
        names = Enum.map_join(removable, ", ", & &1.label)

        changeset =
          Ecto.Changeset.change(%ScaleLevel{})
          |> Ecto.Changeset.add_error(
            :scale_levels,
            "cannot remove scale levels still used by workout variations: #{names}"
          )

        {:error, changeset}
      else
        result =
          Enum.reduce_while(removable, :ok, fn item, :ok ->
            case repo.delete(item) do
              {:ok, _} -> {:cont, :ok}
              {:error, changeset} -> {:halt, {:error, changeset}}
            end
          end)

        case result do
          :ok -> {:ok, :guarded}
          {:error, _} = error -> error
        end
      end
    end)
    |> Multi.run(:upsert_levels, fn repo, %{existing: existing} ->
      existing_by_slug = Map.new(existing, &{&1.slug, &1})
      temporary_levels = Enum.with_index(levels, 1)

      case assign_temporary_scale_orders(repo, existing_by_slug, temporary_levels) do
        {:error, %Ecto.Changeset{} = changeset} ->
          {:error, changeset}

        :ok ->
          levels
          |> Enum.reduce_while({:ok, []}, fn level_params, {:ok, acc} ->
            result =
              case Map.get(existing_by_slug, level_params.slug) do
                nil ->
                  %ScaleLevel{}
                  |> ScaleLevel.changeset(Map.put(level_params, :is_active, true))
                  |> repo.insert()

                %ScaleLevel{} = scale_level ->
                  scale_level
                  |> ScaleLevel.changeset(Map.merge(level_params, %{is_active: true}))
                  |> repo.update()
              end

            case result do
              {:ok, scale_level} -> {:cont, {:ok, [scale_level | acc]}}
              {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
            end
          end)
          |> case do
            {:ok, stored} ->
              {:ok, Enum.reverse(stored)}

            {:error, changeset} ->
              {:error, changeset}
          end
      end
    end)
    |> Multi.run(:normalize, fn repo, _changes ->
      levels =
        repo.all(from scale_level in ScaleLevel, order_by: [asc: scale_level.sort_order])
        |> Enum.map(&normalize_scale_level/1)
        |> Enum.map(fn level -> Map.put(level, :updated_at, now) end)

      {:ok, levels}
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{normalize: scale_levels}} -> {:ok, scale_levels}
      {:error, _step, %Ecto.Changeset{} = changeset, _changes} -> {:error, changeset}
    end
  end

  defp attach_scale_level_ids(params) do
    scale_level_ids =
      list_scale_levels()
      |> Map.new(&{&1.slug, &1.id})

    sections = Map.get(params, :sections) || Map.get(params, "sections") || []

    attach_scale_level_ids_to_sections(sections, scale_level_ids)
    |> case do
      {:ok, updated_sections} ->
        {:ok, Map.put(params, :sections, updated_sections)}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp persist_assigned_workout(%Ecto.Changeset{} = changeset, athlete_ids) do
    if changeset.valid? do
      do_persist_assigned_workout(changeset, athlete_ids)
    else
      {:error, changeset}
    end
  end

  defp do_persist_assigned_workout(changeset, athlete_ids) do
    Multi.new()
    |> Multi.run(:published_workout, fn repo, _changes ->
      workout_id = Ecto.Changeset.get_field(changeset, :master_workout_id)

      case repo.get(MasterWorkout, workout_id) do
        %MasterWorkout{status: :published} = workout ->
          {:ok, workout}

        _ ->
          {:error,
           invalid_assignment_changeset(
             changeset,
             :master_workout_id,
             "must reference a published workout"
           )}
      end
    end)
    |> Multi.insert_or_update(:assignment, changeset)
    |> Multi.run(:athlete_links, fn repo, %{assignment: assignment} ->
      sync_athlete_links(
        repo,
        assignment.id,
        athlete_ids,
        Ecto.Changeset.changed?(changeset, :scheduled_for)
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{assignment: assignment}} ->
        assignment =
          assignment
          |> Repo.preload(@assigned_workout_preloads)
          |> normalize_assignment()

        {:ok, assignment}

      {:error, _step, %Ecto.Changeset{} = assignment_changeset, _changes} ->
        {:error, assignment_changeset}
    end
  end

  defp attach_exercise_scale_level_ids(exercises, scale_level_ids) do
    Enum.reduce_while(exercises, {:ok, []}, fn exercise, {:ok, acc_exercises} ->
      variations = Map.get(exercise, :variations) || Map.get(exercise, "variations") || []

      case attach_variation_scale_level_ids(variations, scale_level_ids) do
        {:ok, updated_variations} ->
          updated_exercise =
            exercise
            |> drop_key("variations")
            |> drop_key(:variations)
            |> Map.put(:variations, updated_variations)

          {:cont, {:ok, [updated_exercise | acc_exercises]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, updated_exercises} -> {:ok, Enum.reverse(updated_exercises)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp attach_variation_scale_level_ids(variations, scale_level_ids) do
    Enum.reduce_while(variations, {:ok, []}, fn variation, {:ok, acc_variations} ->
      slug =
        Map.get(variation, :scale_level_slug) ||
          Map.get(variation, "scale_level_slug") ||
          Map.get(variation, :scale_level) ||
          Map.get(variation, "scale_level")

      case Map.fetch(scale_level_ids, slug) do
        {:ok, scale_level_id} ->
          updated_variation =
            variation
            |> drop_key("scale_level_slug")
            |> drop_key(:scale_level_slug)
            |> drop_key("scale_level")
            |> drop_key(:scale_level)
            |> Map.put(:scale_level_id, scale_level_id)

          {:cont, {:ok, [updated_variation | acc_variations]}}

        :error ->
          changeset =
            Ecto.Changeset.change(%ExerciseVariation{})
            |> Ecto.Changeset.add_error(
              :scale_level_id,
              "unknown active scale level: #{slug}"
            )

          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, updated_variations} -> {:ok, Enum.reverse(updated_variations)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_workout(%MasterWorkout{} = workout, opts \\ []) do
    note_visibility = Keyword.get(opts, :note_visibility, :athlete)
    sections = normalize_sections(workout.sections, note_visibility: note_visibility)

    normalized = %{
      id: workout.id,
      # Callers need the owning organization for tenant-scoped side effects
      # (e.g. broadcast targeting) without reaching into the session GUC.
      organization_id: workout.organization_id,
      title: workout.title,
      subtitle: workout.subtitle,
      description: workout.description,
      type: workout.type |> to_string(),
      status: workout.status |> to_string(),
      is_team_workout: workout.is_team_workout,
      difficulty: workout.difficulty,
      estimated_duration_seconds: workout.estimated_duration_seconds,
      equipment: workout.equipment,
      tags: workout.tags,
      notes: visible_notes(workout.notes, note_visibility),
      workout_metadata: workout.workout_metadata,
      created_by_id: workout.created_by_id,
      folder_id: workout.folder_id,
      source_workout_id: workout.source_workout_id,
      inserted_at: workout.inserted_at,
      updated_at: workout.updated_at,
      sections: sections
    }

    Map.put(normalized, :available_scale_levels, WorkoutMaterializer.available_scales(normalized))
  end

  defp normalize_assignment(%AssignedWorkout{} = assignment) do
    %{
      id: assignment.id,
      master_workout_id: assignment.master_workout_id,
      scheduled_for: Date.to_iso8601(assignment.scheduled_for),
      admin_notes: assignment.admin_notes,
      inserted_at: assignment.inserted_at,
      athlete_ids: Enum.map(assignment.athlete_links, & &1.athlete_id),
      workout: normalize_assigned_workout(assignment.master_workout)
    }
  end

  defp normalize_assignment_for_athlete(%AssignedWorkout{} = assignment, athlete_id) do
    link = Enum.find(assignment.athlete_links, &(&1.athlete_id == athlete_id))
    my_status = link && link.athlete_status && to_string(link.athlete_status)

    assignment
    |> normalize_assignment()
    |> Map.put(:athlete_ids, [athlete_id])
    |> Map.put(:scheduled_for, Date.to_iso8601(link.scheduled_for))
    |> Map.put(:my_athlete_status, my_status)
  end

  defp fetch_completed_assignment_executions(_athlete_id, []), do: %{}

  defp fetch_completed_assignment_executions(athlete_id, assignment_ids) do
    WorkoutExecution
    |> where(
      [e],
      e.user_id == ^athlete_id and
        e.source == :assigned and
        e.source_reference_id in ^assignment_ids and
        not is_nil(e.completed_at_utc)
    )
    |> order_by([e], desc: e.completed_at_utc)
    |> select([e], %{
      source_reference_id: e.source_reference_id,
      section_scores: e.section_scores
    })
    |> Repo.all()
    |> Enum.group_by(& &1.source_reference_id)
    |> Map.new(fn {id, [first | _rest]} -> {id, first} end)
  end

  defp normalize_exercise(%WorkoutExercise{} = exercise, note_visibility) do
    %{
      id: exercise.id,
      name: exercise.name,
      subtitle: exercise.subtitle,
      exercise_ref: exercise.exercise_ref,
      item_type: to_string(exercise.item_type),
      sets: exercise.sets,
      set_prescriptions: exercise.set_prescriptions,
      prescription_value: exercise.prescription_value,
      prescription_unit: exercise.prescription_unit && to_string(exercise.prescription_unit),
      load_value: exercise.load_value,
      load_mode: exercise.load_mode && to_string(exercise.load_mode),
      load_progression: exercise.load_progression,
      superset_group_id: exercise.superset_group_id,
      alternating_group_id: exercise.alternating_group_id,
      hr_zone: exercise.hr_zone,
      tempo: exercise.tempo,
      rest_seconds: exercise.rest_seconds,
      cluster_rest_seconds: exercise.cluster_rest_seconds,
      rest_pause_seconds: exercise.rest_pause_seconds,
      pacing: exercise.pacing,
      interval_assignment: exercise.interval_assignment,
      note: exercise.note,
      notes: visible_notes(exercise.notes, note_visibility),
      prescription_metadata: exercise.prescription_metadata,
      group_config: visible_group_config(exercise.group_config, note_visibility),
      order: exercise.order,
      variations:
        exercise.variations
        |> Enum.sort_by(&{&1.scale_level.sort_order || 0, &1.scale_level.slug})
        |> Enum.map(&normalize_variation(&1, note_visibility))
    }
  end

  defp normalize_variation(%ExerciseVariation{} = variation, note_visibility) do
    %{
      id: variation.id,
      exercise_name_override: variation.exercise_name_override,
      sets: variation.sets,
      set_prescriptions: variation.set_prescriptions,
      prescription_value: variation.prescription_value,
      prescription_unit: variation.prescription_unit && to_string(variation.prescription_unit),
      load_value: variation.load_value,
      load_mode: variation.load_mode && to_string(variation.load_mode),
      load_progression: variation.load_progression,
      excluded: variation.excluded,
      note: variation.note,
      notes: visible_notes(variation.notes, note_visibility),
      prescription_metadata: variation.prescription_metadata,
      scale_level: normalize_scale_level(variation.scale_level)
    }
  end

  defp insert_sections(workout_id, params) do
    sections = Map.get(params, :sections) || Map.get(params, "sections") || []

    insert_sections(workout_id, sections, nil)
  end

  defp sections_have_exercises?(sections) do
    Enum.any?(sections, fn section ->
      exercises = Map.get(section, "exercises") || Map.get(section, :exercises) || []
      children = Map.get(section, "sections") || Map.get(section, :sections) || []

      Enum.any?(exercises, fn item ->
        (Map.get(item, "item_type") || Map.get(item, :item_type) || "exercise") == "exercise"
      end) or sections_have_exercises?(children)
    end)
  end

  defp insert_sections(_workout_id, [], _parent_section_id), do: {:ok, []}

  defp insert_sections(workout_id, sections, parent_section_id) do
    Enum.reduce_while(sections, {:ok, []}, fn section_params, {:ok, acc_sections} ->
      exercises =
        Map.get(section_params, :exercises) || Map.get(section_params, "exercises") || []

      child_sections =
        Map.get(section_params, :sections) || Map.get(section_params, "sections") || []

      section_params =
        section_params
        |> drop_key(:exercises)
        |> drop_key("exercises")
        |> drop_key(:sections)
        |> drop_key("sections")
        |> Map.put("master_workout_id", workout_id)
        |> maybe_put("parent_section_id", parent_section_id)

      case %WorkoutSection{}
           |> WorkoutSection.persist_changeset(section_params)
           |> Repo.insert() do
        {:ok, section} ->
          case insert_exercises(section.id, exercises) do
            {:ok, _exercises} ->
              case insert_sections(workout_id, child_sections, section.id) do
                {:ok, nested_sections} ->
                  branch = [section | nested_sections]
                  {:cont, {:ok, Enum.reverse(branch) ++ acc_sections}}

                error ->
                  {:halt, error}
              end

            error ->
              {:halt, error}
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, stored_sections} -> {:ok, Enum.reverse(stored_sections)}
      error -> error
    end
  end

  defp insert_exercises(section_id, exercises) do
    exercises
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, []}, fn {exercise_params, order}, {:ok, acc_exercises} ->
      variations =
        Map.get(exercise_params, :variations) || Map.get(exercise_params, "variations") || []

      exercise_params =
        exercise_params
        |> drop_key(:variations)
        |> drop_key("variations")
        |> Map.put("order", order)
        |> Map.put("workout_section_id", section_id)

      case %WorkoutExercise{} |> WorkoutExercise.changeset(exercise_params) |> Repo.insert() do
        {:ok, exercise} ->
          case insert_variations(exercise.id, variations) do
            {:ok, _variations} -> {:cont, {:ok, [exercise | acc_exercises]}}
            error -> {:halt, error}
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, stored_exercises} -> {:ok, Enum.reverse(stored_exercises)}
      error -> error
    end
  end

  defp insert_variations(exercise_id, variations) do
    Enum.reduce_while(variations, {:ok, []}, fn variation_params, {:ok, acc_variations} ->
      variation_params =
        variation_params
        |> stringify_keys_deep()
        |> Map.put("workout_exercise_id", exercise_id)

      case %ExerciseVariation{}
           |> ExerciseVariation.changeset(variation_params)
           |> Repo.insert() do
        {:ok, variation} -> {:cont, {:ok, [variation | acc_variations]}}
        {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, stored_variations} -> {:ok, Enum.reverse(stored_variations)}
      error -> error
    end
  end

  defp extract_top_level_draft_fields(draft_data) when is_map(draft_data) do
    %{}
    |> maybe_put(:title, get_map_value(draft_data, :title))
    |> maybe_put(:type, get_map_value(draft_data, :type))
    |> maybe_put(:is_team_workout, get_map_value(draft_data, :is_team_workout))
    |> maybe_put(:subtitle, get_map_value(draft_data, :subtitle))
    |> maybe_put(:description, get_map_value(draft_data, :description))
    |> maybe_put(:difficulty, get_map_value(draft_data, :difficulty))
    |> maybe_put(
      :estimated_duration_seconds,
      get_map_value(draft_data, :estimated_duration_seconds)
    )
    |> maybe_put(:equipment, get_map_value(draft_data, :equipment))
    |> maybe_put(:tags, get_map_value(draft_data, :tags))
    |> maybe_put(:notes, get_map_value(draft_data, :notes))
    |> maybe_put(:workout_metadata, get_map_value(draft_data, :workout_metadata))
  end

  defp extract_top_level_draft_fields(_draft_data), do: %{}

  defp extract_dsl_authoring_fields(params) do
    %{}
    |> maybe_put(:authoring_mode, get_map_value(params, :authoring_mode))
    |> maybe_put(:dsl_version, get_map_value(params, :dsl_version))
    |> maybe_put(:dsl_source, get_map_value(params, :dsl_source))
    |> maybe_put(:dsl_document, get_map_value(params, :dsl_document))
    |> maybe_put(:last_dsl_diagnostics, get_map_value(params, :last_dsl_diagnostics))
    |> maybe_put(:free_text_body, get_map_value(params, :free_text_body))
    |> maybe_put(:free_text_document, get_map_value(params, :free_text_document))
  end

  defp validate_expected_revision(workout, params) do
    case get_map_value(params, :expected_source_revision) do
      nil -> :ok
      revision when revision == workout.dsl_source_revision -> :ok
      _revision -> {:error, :stale_dsl_revision}
    end
  end

  defp maybe_lock_dsl_revision(changeset, params) do
    if get_map_value(params, :expected_source_revision) == nil do
      changeset
    else
      Ecto.Changeset.optimistic_lock(changeset, :dsl_source_revision)
    end
  end

  defp draft_summary(workout) do
    %{
      id: workout.id,
      status: to_string(workout.status),
      authoring_mode: workout.authoring_mode,
      dsl_source_revision: workout.dsl_source_revision
    }
  end

  defp authoring_state(workout) do
    %{
      authoring_mode: workout.authoring_mode,
      dsl_version: workout.dsl_version,
      dsl_source: workout.dsl_source,
      dsl_document: workout.dsl_document,
      dsl_source_revision: workout.dsl_source_revision,
      last_dsl_diagnostics: workout.last_dsl_diagnostics,
      free_text_body: workout.free_text_body,
      free_text_document: workout.free_text_document
    }
  end

  defp publish_locked_workout(nil, _params), do: {:error, :not_found}

  defp publish_locked_workout(%MasterWorkout{status: :published, draft_data: nil}, _params),
    do: {:error, :already_published}

  defp publish_locked_workout(workout, params) do
    with :ok <- validate_expected_revision(workout, params),
         merged_params <- merge_publish_params(workout, params),
         {:ok, prepared_params} <- prepare_workout_structure(merged_params),
         prepared_params <- stringify_keys_deep(prepared_params),
         :ok <- validate_publish_body(prepared_params),
         {:ok, params_with_levels} <- attach_scale_level_ids(prepared_params),
         {:ok, published} <-
           workout
           |> MasterWorkout.publish_changeset(prepared_params)
           |> Repo.update(),
         {_count, _rows} <- Repo.delete_all(Ecto.assoc(workout, :sections)),
         {:ok, _sections} <- insert_sections(published.id, params_with_levels) do
      {:ok, published}
    end
  end

  defp merge_publish_params(workout, params) do
    params = stringify_keys_deep(params)

    (workout.draft_data || %{})
    |> Map.merge(params)
    |> Map.merge(stringify_keys_deep(extract_dsl_authoring_fields(params)))
    |> stringify_keys_deep()
  end

  defp validate_publish_body(%{"authoring_mode" => "free_text"} = params) do
    body = Map.get(params, "free_text_body")

    if is_binary(body) and String.trim(body) != "" do
      :ok
    else
      {:error, :no_free_text_body}
    end
  end

  defp validate_publish_body(params), do: validate_publish_sections(params)

  defp validate_publish_sections(params) do
    sections = Map.get(params, "sections") || []

    if sections == [] or not sections_have_exercises?(sections) do
      {:error, :no_sections}
    else
      :ok
    end
  end

  defp extract_sections_from_draft(draft_data) when is_map(draft_data) do
    get_map_value(draft_data, :sections) || []
  end

  defp extract_sections_from_draft(_draft_data), do: []

  defp get_map_value(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp stringify_keys_deep(value) when is_list(value), do: Enum.map(value, &stringify_keys_deep/1)

  defp stringify_keys_deep(value) when is_map(value) do
    value
    |> Enum.map(fn {key, nested_value} -> {to_string(key), stringify_keys_deep(nested_value)} end)
    |> Map.new()
  end

  defp stringify_keys_deep(value), do: value

  defp normalize_assigned_workout(%MasterWorkout{} = workout) do
    %{
      id: workout.id,
      title: workout.title,
      subtitle: workout.subtitle,
      description: workout.description,
      type: workout.type |> to_string(),
      is_team_workout: workout.is_team_workout,
      difficulty: workout.difficulty,
      estimated_duration_seconds: workout.estimated_duration_seconds,
      equipment: workout.equipment,
      tags: workout.tags,
      notes: visible_notes(workout.notes, :athlete),
      workout_metadata: workout.workout_metadata,
      authoring_mode: workout.authoring_mode,
      free_text_body: workout.free_text_body,
      free_text_document: workout.free_text_document,
      sections: normalize_sections(workout.sections, note_visibility: :athlete)
    }
  end

  defp normalize_sections(sections, opts) do
    note_visibility = Keyword.get(opts, :note_visibility, :athlete)

    exercise_mapper =
      Keyword.get(opts, :exercise_mapper, &normalize_exercise(&1, note_visibility))

    sections
    |> Enum.group_by(& &1.parent_section_id)
    |> flatten_sections(nil, nil, exercise_mapper, note_visibility)
  end

  defp flatten_sections(
         grouped_sections,
         parent_section_id,
         inherited_timer_config,
         exercise_mapper,
         note_visibility
       ) do
    grouped_sections
    |> Map.get(parent_section_id, [])
    |> Enum.sort_by(& &1.order)
    |> Enum.flat_map(fn section ->
      effective_timer_config = section.timer_config || inherited_timer_config

      normalized_section = %{
        id: section.id,
        parent_section_id: section.parent_section_id,
        name: section.name,
        subtitle: section.subtitle,
        order: section.order,
        scoreable: section.scoreable,
        score_config: section.score_config,
        timer_config: effective_timer_config,
        note: section.note,
        notes: visible_notes(section.notes, note_visibility),
        rest_before_next_section_seconds: section.rest_before_next_section_seconds,
        section_metadata: section.section_metadata,
        exercises:
          section.exercises
          |> Enum.sort_by(& &1.order)
          |> Enum.map(exercise_mapper)
      }

      [
        normalized_section
        | flatten_sections(
            grouped_sections,
            section.id,
            effective_timer_config,
            exercise_mapper,
            note_visibility
          )
      ]
    end)
  end

  defp attach_scale_level_ids_to_sections(sections, scale_level_ids) do
    Enum.reduce_while(sections, {:ok, []}, fn section, {:ok, acc_sections} ->
      exercises = Map.get(section, :exercises) || Map.get(section, "exercises") || []
      child_sections = Map.get(section, :sections) || Map.get(section, "sections") || []

      with {:ok, updated_exercises} <-
             attach_exercise_scale_level_ids(exercises, scale_level_ids),
           {:ok, updated_child_sections} <-
             attach_scale_level_ids_to_sections(child_sections, scale_level_ids) do
        updated_section =
          section
          |> drop_key("exercises")
          |> drop_key(:exercises)
          |> drop_key("sections")
          |> drop_key(:sections)
          |> Map.put(:exercises, updated_exercises)
          |> maybe_put_children(updated_child_sections)

        {:cont, {:ok, [updated_section | acc_sections]}}
      else
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, updated_sections} -> {:ok, Enum.reverse(updated_sections)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp sync_athlete_links(repo, assignment_id, athlete_ids, reset_scheduled_for?) do
    assignment_date =
      repo.one!(
        from assignment in AssignedWorkout,
          where: assignment.id == ^assignment_id,
          select: assignment.scheduled_for
      )

    existing_athlete_ids =
      repo.all(
        from link in AssignedWorkoutAthlete,
          where: link.assigned_workout_id == ^assignment_id,
          select: link.athlete_id
      )

    archived_links =
      repo.all(
        from link in AssignedWorkoutAthlete,
          where:
            link.assigned_workout_id == ^assignment_id and
              link.athlete_id in ^athlete_ids and
              link.athlete_status == :archived
      )

    Enum.each(archived_links, fn link ->
      link
      |> Ecto.Changeset.change(athlete_status: nil)
      |> repo.update!()
    end)

    ids_to_remove = existing_athlete_ids -- athlete_ids

    if ids_to_remove != [] do
      repo.delete_all(
        from link in AssignedWorkoutAthlete,
          where: link.assigned_workout_id == ^assignment_id and link.athlete_id in ^ids_to_remove
      )
    end

    if reset_scheduled_for? and existing_athlete_ids != [] do
      AssignedWorkoutAthlete
      |> where(
        [link],
        link.assigned_workout_id == ^assignment_id and
          link.athlete_id in ^existing_athlete_ids
      )
      |> repo.all()
      |> Enum.each(fn link ->
        link
        |> AssignedWorkoutAthlete.reschedule_changeset(assignment_date)
        |> repo.update!()
      end)
    end

    (athlete_ids -- existing_athlete_ids)
    |> Enum.reduce_while({:ok, []}, fn athlete_id, {:ok, acc} ->
      case %AssignedWorkoutAthlete{}
           |> AssignedWorkoutAthlete.changeset(%{
             assigned_workout_id: assignment_id,
             athlete_id: athlete_id,
             scheduled_for: assignment_date
           })
           |> repo.insert() do
        {:ok, link} -> {:cont, {:ok, [link | acc]}}
        {:error, %Ecto.Changeset{} = athlete_changeset} -> {:halt, {:error, athlete_changeset}}
      end
    end)
    |> case do
      {:ok, links} -> {:ok, Enum.reverse(links)}
      {:error, %Ecto.Changeset{} = athlete_changeset} -> {:error, athlete_changeset}
    end
  end

  defp maybe_put_children(map, []), do: map
  defp maybe_put_children(map, children), do: Map.put(map, :sections, children)

  defp normalize_scale_level(%ScaleLevel{} = scale_level) do
    %{
      id: scale_level.id,
      slug: scale_level.slug,
      label: scale_level.label,
      sort_order: scale_level.sort_order,
      is_active: scale_level.is_active
    }
  end

  defp normalize_scale_level_params(params) do
    %{
      slug: Map.get(params, :slug) || Map.get(params, "slug"),
      label: Map.get(params, :label) || Map.get(params, "label"),
      sort_order: Map.get(params, :sort_order) || Map.get(params, "sort_order")
    }
  end

  defp validate_scale_level_list(changeset, levels) do
    changeset
    |> maybe_add_empty_scale_level_error(levels)
    |> validate_unique_values(levels, :slug, "must be unique")
    |> validate_unique_values(levels, :sort_order, "must be unique")
    |> validate_sequential_sort_orders(levels)
  end

  defp maybe_add_empty_scale_level_error(changeset, levels) do
    if levels == [] do
      Ecto.Changeset.add_error(changeset, :scale_levels, "must include at least one scale level")
    else
      changeset
    end
  end

  defp validate_unique_values(changeset, levels, field, message) do
    values = Enum.map(levels, &Map.get(&1, field))

    if Enum.uniq(values) == values do
      changeset
    else
      Ecto.Changeset.add_error(changeset, field, message)
    end
  end

  defp validate_sequential_sort_orders(changeset, levels) do
    if levels == [] do
      changeset
    else
      expected = Enum.to_list(1..length(levels))
      actual = levels |> Enum.map(& &1.sort_order) |> Enum.sort()

      if actual == expected do
        changeset
      else
        Ecto.Changeset.add_error(
          changeset,
          :scale_levels,
          "sort_order must be sequential from 1 to #{length(levels)}"
        )
      end
    end
  end

  defp blank_scale_level?(%{slug: slug, label: label}) do
    blank?(slug) and blank?(label)
  end

  defp validate_assignment_athletes(changeset, athlete_ids) do
    if athlete_ids == [] do
      Ecto.Changeset.add_error(changeset, :athlete_ids, "must include at least one athlete")
    else
      changeset
    end
  end

  defp invalid_assignment_changeset(changeset, field, message) do
    Ecto.Changeset.add_error(changeset, field, message)
  end

  defp existing_athlete_ids(%AssignedWorkout{} = assignment) do
    assignment
    |> Repo.preload(:athlete_links)
    |> Map.get(:athlete_links)
    |> Enum.map(& &1.athlete_id)
  end

  defp find_assignment_by_workout_date_and_notes(nil, _scheduled_for, _admin_notes), do: nil
  defp find_assignment_by_workout_date_and_notes(_workout_id, nil, _admin_notes), do: nil

  defp find_assignment_by_workout_date_and_notes(workout_id, scheduled_for, admin_notes) do
    AssignedWorkout
    |> where(
      [assignment],
      assignment.master_workout_id == ^workout_id and assignment.scheduled_for == ^scheduled_for
    )
    |> maybe_scope_by_admin_notes(admin_notes)
    |> Repo.one()
  end

  defp find_conflicting_assignment(_master_workout_id, nil, _admin_notes, _current_id), do: nil

  defp find_conflicting_assignment(master_workout_id, scheduled_for, admin_notes, current_id) do
    base_query =
      AssignedWorkout
      |> where(
        [assignment],
        assignment.master_workout_id == ^master_workout_id and
          assignment.scheduled_for == ^scheduled_for and assignment.id != ^current_id
      )

    base_query
    |> maybe_scope_by_admin_notes(admin_notes)
    |> Repo.one()
  end

  defp normalize_admin_notes_input(params) do
    params
    |> Map.get(:admin_notes, Map.get(params, "admin_notes"))
    |> case do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      value ->
        value
    end
  end

  defp maybe_scope_by_admin_notes(query, nil) do
    where(query, [assignment], is_nil(assignment.admin_notes))
  end

  defp maybe_scope_by_admin_notes(query, admin_notes) do
    where(query, [assignment], assignment.admin_notes == ^admin_notes)
  end

  defp consolidate_assigned_workouts(
         %Ecto.Changeset{} = changeset,
         _conflicting_assignment,
         _athlete_ids
       )
       when not changeset.valid? do
    {:error, changeset}
  end

  defp consolidate_assigned_workouts(
         %Ecto.Changeset{} = changeset,
         %AssignedWorkout{} = conflicting_assignment,
         athlete_ids
       ) do
    current_assignment = changeset.data

    merged_athlete_ids =
      (existing_athlete_ids(current_assignment) ++
         existing_athlete_ids(conflicting_assignment) ++ athlete_ids)
      |> Enum.uniq()

    Multi.new()
    |> Multi.delete(:conflicting_assignment, conflicting_assignment)
    |> Multi.update(:assignment, changeset)
    |> Multi.run(:athlete_links, fn repo, %{assignment: assignment} ->
      sync_athlete_links(repo, assignment.id, merged_athlete_ids, false)
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{assignment: assignment}} ->
        assignment =
          assignment
          |> Repo.preload(@assigned_workout_preloads)
          |> normalize_assignment()

        {:ok, assignment}

      {:error, :assignment, %Ecto.Changeset{} = assignment_changeset, _changes} ->
        {:error, assignment_changeset}

      {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp reconstruct_draft_data(%MasterWorkout{} = workout) do
    %{
      "title" => workout.title,
      "subtitle" => workout.subtitle,
      "description" => workout.description,
      "type" => workout.type && to_string(workout.type),
      "is_team_workout" => workout.is_team_workout,
      "difficulty" => workout.difficulty,
      "estimated_duration_seconds" => workout.estimated_duration_seconds,
      "equipment" => workout.equipment,
      "tags" => workout.tags,
      "notes" => workout.notes,
      "workout_metadata" => workout.workout_metadata,
      "sections" => draft_sections_from_db(workout.sections)
    }
  end

  defp draft_sections_from_db(sections) do
    sections
    |> Enum.group_by(& &1.parent_section_id)
    |> draft_section_group(nil)
  end

  defp draft_section_group(grouped, parent_id) do
    Map.get(grouped, parent_id, [])
    |> Enum.sort_by(& &1.order)
    |> Enum.map(fn section ->
      base = %{
        "id" => section.id,
        "name" => section.name,
        "subtitle" => section.subtitle,
        "note" => section.note,
        "notes" => section.notes,
        "rest_before_next_section_seconds" => section.rest_before_next_section_seconds,
        "section_metadata" => section.section_metadata,
        "scoreable" => section.scoreable,
        "timer_config" => section.timer_config,
        "score_config" => section.score_config,
        "exercises" =>
          section.exercises
          |> Enum.sort_by(& &1.order)
          |> Enum.map(&draft_exercise_from_db/1)
      }

      children = draft_section_group(grouped, section.id)
      if children == [], do: base, else: Map.put(base, "sections", children)
    end)
  end

  defp draft_exercise_from_db(%WorkoutExercise{} = exercise) do
    %{
      "id" => exercise.id,
      "name" => exercise.name,
      "subtitle" => exercise.subtitle,
      "exercise_ref" => exercise.exercise_ref,
      "item_type" => to_string(exercise.item_type),
      "sets" => exercise.sets,
      "set_prescriptions" => exercise.set_prescriptions,
      "prescription_value" => exercise.prescription_value,
      "prescription_unit" => exercise.prescription_unit && to_string(exercise.prescription_unit),
      "load_value" => exercise.load_value,
      "load_mode" => exercise.load_mode && to_string(exercise.load_mode),
      "load_progression" => exercise.load_progression,
      "superset_group_id" => exercise.superset_group_id,
      "alternating_group_id" => exercise.alternating_group_id,
      "hr_zone" => exercise.hr_zone,
      "tempo" => exercise.tempo,
      "rest_seconds" => exercise.rest_seconds,
      "cluster_rest_seconds" => exercise.cluster_rest_seconds,
      "rest_pause_seconds" => exercise.rest_pause_seconds,
      "pacing" => exercise.pacing,
      "interval_assignment" => exercise.interval_assignment,
      "note" => exercise.note,
      "notes" => exercise.notes,
      "prescription_metadata" => exercise.prescription_metadata,
      "group_config" => exercise.group_config,
      "variations" => Enum.map(exercise.variations, &draft_variation_from_db/1)
    }
  end

  defp draft_variation_from_db(%ExerciseVariation{} = variation) do
    %{
      "id" => variation.id,
      "scale_level_slug" => variation.scale_level.slug,
      "exercise_name_override" => variation.exercise_name_override,
      "sets" => variation.sets,
      "set_prescriptions" => variation.set_prescriptions,
      "prescription_value" => variation.prescription_value,
      "prescription_unit" =>
        variation.prescription_unit && to_string(variation.prescription_unit),
      "load_value" => variation.load_value,
      "load_mode" => variation.load_mode && to_string(variation.load_mode),
      "load_progression" => variation.load_progression,
      "excluded" => variation.excluded,
      "note" => variation.note,
      "notes" => variation.notes,
      "prescription_metadata" => variation.prescription_metadata
    }
  end

  defp visible_notes(notes, :admin), do: notes || []

  defp visible_notes(notes, _visibility) do
    Enum.reject(notes || [], fn note ->
      type = Map.get(note, "type") || Map.get(note, :type)
      type == "coach-note"
    end)
  end

  defp visible_group_config(nil, _visibility), do: nil

  defp visible_group_config(config, visibility) do
    notes = Map.get(config, "notes") || Map.get(config, :notes) || []

    config
    |> stringify_keys_deep()
    |> Map.put("notes", visible_notes(notes, visibility))
  end

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp drop_key(map, key) do
    if Map.has_key?(map, key), do: Map.delete(map, key), else: map
  end

  @impl true
  def reject_assignment_for_athlete(assignment_id, athlete_id) do
    link =
      AssignedWorkoutAthlete
      |> where(
        [link],
        link.assigned_workout_id == ^assignment_id and link.athlete_id == ^athlete_id
      )
      |> Repo.one()

    case link do
      nil ->
        {:error, :not_found}

      %AssignedWorkoutAthlete{athlete_status: :rejected} ->
        {:error, :already_rejected}

      %AssignedWorkoutAthlete{} = link ->
        link
        |> AssignedWorkoutAthlete.reject_changeset()
        |> Repo.update()
        |> case do
          {:ok, updated_link} ->
            case AssignedWorkout |> scoped_to_tenant() |> Repo.get(assignment_id) do
              nil ->
                {:error, :not_found}

              assignment ->
                normalized =
                  assignment
                  |> Repo.preload(@assigned_workout_preloads)
                  |> normalize_assignment()

                {:ok, Map.put(normalized, :rejection_link_id, updated_link.id)}
            end

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp assign_temporary_scale_orders(repo, existing_by_slug, levels_with_index) do
    levels_with_index
    |> Enum.reduce_while(:ok, fn {level_params, index}, :ok ->
      case Map.get(existing_by_slug, level_params.slug) do
        nil ->
          {:cont, :ok}

        %ScaleLevel{} = scale_level ->
          result =
            scale_level
            |> Ecto.Changeset.change(%{sort_order: -index, is_active: true})
            |> repo.update()

          case result do
            {:ok, _updated_scale_level} -> {:cont, :ok}
            {:error, %Ecto.Changeset{} = changeset} -> {:halt, {:error, changeset}}
          end
      end
    end)
  end

  @impl true
  def reopen_workout(id) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %MasterWorkout{status: :draft} ->
        {:error, :not_published}

      %MasterWorkout{status: :published, draft_data: draft_data} = workout
      when not is_nil(draft_data) ->
        {:ok, %{id: workout.id, status: "published"}}

      %MasterWorkout{status: :published} = workout ->
        workout_with_sections = Repo.preload(workout, @workout_preloads)
        draft_data = reconstruct_draft_data(workout_with_sections)

        case workout
             |> Ecto.Changeset.change(draft_data: draft_data)
             |> Repo.update() do
          {:ok, reopened} -> {:ok, %{id: reopened.id, status: "published"}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def get_assigned_workout(id) do
    case AssignedWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        nil

      %AssignedWorkout{} = assignment ->
        assignment = Repo.preload(assignment, :athlete_links)

        %{
          id: assignment.id,
          athlete_ids: Enum.map(assignment.athlete_links, & &1.athlete_id),
          athlete_scheduled_for:
            Map.new(assignment.athlete_links, &{&1.athlete_id, &1.scheduled_for}),
          scheduled_for: assignment.scheduled_for
        }
    end
  end

  @impl true
  def get_assignment_execution_access(assignment_id, athlete_id) do
    AssignedWorkout
    |> join(:inner, [assignment], link in AssignedWorkoutAthlete,
      on: link.assigned_workout_id == assignment.id
    )
    |> where(
      [assignment, link],
      assignment.id == ^assignment_id and link.athlete_id == ^athlete_id and
        (is_nil(link.athlete_status) or link.athlete_status != :archived)
    )
    |> select([assignment, link], %{
      assignment_id: assignment.id,
      master_workout_id: assignment.master_workout_id,
      athlete_status: link.athlete_status,
      organization_id: assignment.organization_id
    })
    |> Repo.one()
    |> case do
      nil ->
        nil

      access ->
        %{access | athlete_status: access.athlete_status && to_string(access.athlete_status)}
    end
  end

  @impl true
  def duplicate_workout(id, title_suffix, attrs) do
    case MasterWorkout |> scoped_to_tenant() |> Repo.get(id) do
      nil ->
        {:error, :not_found}

      %MasterWorkout{} = source ->
        title = (source.title || "Untitled") <> " " <> title_suffix
        draft_data = build_duplicate_draft_data(source, title)

        params = %{
          created_by_id: source.created_by_id,
          status: :draft,
          title: title,
          type: source.type,
          folder_id: Map.get(attrs, :folder_id) || Map.get(attrs, "folder_id"),
          source_workout_id: source.id,
          draft_data: draft_data
        }

        case %MasterWorkout{} |> MasterWorkout.draft_changeset(params) |> Repo.insert() do
          {:ok, new_workout} -> {:ok, %{id: new_workout.id, status: "draft", title: title}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  defp scoped_to_tenant(query) do
    case RepoContext.current_setting("app.organization_id") do
      organization_id when is_binary(organization_id) ->
        where(query, [row], row.organization_id == ^organization_id)

      _no_tenant_context ->
        query
    end
  end

  defp normalize_folder(folder) do
    %{
      id: folder.id,
      name: folder.name,
      parent_id: folder.parent_id,
      created_by_id: folder.created_by_id,
      inserted_at: folder.inserted_at,
      updated_at: folder.updated_at
    }
  end

  defp validate_folder_parent(folder, params) do
    parent_id = Map.get(params, :parent_id) || Map.get(params, "parent_id")
    folder_id = folder && folder.id

    cond do
      is_nil(parent_id) or parent_id == "" ->
        :ok

      parent_id == folder_id ->
        {:error, :folder_cycle}

      is_nil(WorkoutFolder |> scoped_to_tenant() |> Repo.get(parent_id)) ->
        {:error, :folder_parent_not_found}

      folder_id && descendant_folder?(parent_id, folder_id) ->
        {:error, :folder_cycle}

      true ->
        :ok
    end
  end

  defp descendant_folder?(candidate_id, ancestor_id) do
    case WorkoutFolder |> scoped_to_tenant() |> Repo.get(candidate_id) do
      nil -> false
      %{parent_id: nil} -> false
      %{parent_id: ^ancestor_id} -> true
      %{parent_id: parent_id} -> descendant_folder?(parent_id, ancestor_id)
    end
  end

  defp build_duplicate_draft_data(source, title) do
    base = source.draft_data || %{}
    existing_sections = Map.get(base, "sections", Map.get(base, :sections))

    if is_list(existing_sections) && existing_sections != [] do
      base
      |> Map.put("title", title)
      |> Map.put("type", source.type && to_string(source.type))
    else
      source
      |> Repo.preload(@workout_preloads)
      |> reconstruct_draft_data()
      |> Map.put("title", title)
    end
  end

  defp prepare_workout_structure(params) do
    case WorkoutAuthoring.prepare_structure(params) do
      {:ok, normalized} ->
        {:ok, normalized}

      {:error, reason} ->
        changeset =
          Ecto.Changeset.change(%WorkoutExercise{})
          |> Ecto.Changeset.add_error(:set_composition, Atom.to_string(reason))

        {:error, changeset}
    end
  end

  @impl true
  def substitute_assignment_workout(assignment_id, new_workout_id) do
    case AssignedWorkout |> scoped_to_tenant() |> Repo.get(assignment_id) do
      nil ->
        {:error, :not_found}

      %AssignedWorkout{} = assignment ->
        case MasterWorkout |> scoped_to_tenant() |> Repo.get(new_workout_id) do
          nil ->
            {:error, :workout_not_found}

          %MasterWorkout{status: :draft} ->
            {:error, :workout_not_published}

          %MasterWorkout{status: :published} ->
            case assignment
                 |> Ecto.Changeset.change(master_workout_id: new_workout_id)
                 |> Repo.update() do
              {:ok, updated} -> {:ok, %{id: updated.id}}
              {:error, changeset} -> {:error, changeset}
            end
        end
    end
  end

  # Auth used to be decided here via the caller's *global* `role`, which let
  # any account with the global :admin role (not just staff of this
  # assignment's own organization) into the messaging thread it authorizes -
  # a cross-tenant IDOR. Authorization now happens in the caller
  # (GetOrCreateMessagingThread), which can check the actor's organization
  # membership; this just fetches.
  @impl true
  def get_assignment(assignment_id) do
    case AssignedWorkout
         |> Repo.get(assignment_id)
         |> Repo.preload(:athlete_links) do
      nil -> {:error, :not_found}
      %AssignedWorkout{} = assignment -> {:ok, assignment}
    end
  end

  @impl true
  def update_assignment_date(id, athlete_id, new_date) do
    case Repo.get_by(AssignedWorkoutAthlete, assigned_workout_id: id, athlete_id: athlete_id) do
      nil ->
        {:error, :not_found}

      link ->
        link
        |> AssignedWorkoutAthlete.reschedule_changeset(new_date)
        |> Repo.update()
        |> case do
          {:ok, _updated} ->
            assignment =
              AssignedWorkout
              |> Repo.get!(id)
              |> Repo.preload(@assigned_workout_preloads)

            {:ok, normalize_assignment_for_athlete(assignment, athlete_id)}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  @impl true
  def delete_superseded_drafts(published_id, admin_id) do
    MasterWorkout
    |> where(
      [w],
      w.status == :draft and w.created_by_id == ^admin_id and w.id != ^published_id
    )
    |> Repo.delete_all()

    :ok
  end
end
