defmodule MilosTraining.Infrastructure.Workouts.EctoWorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  import Ecto.Query

  alias Ecto.Multi

  alias MilosTraining.{
    Execution.WorkoutExecution,
    Repo,
    ScaleLevel,
    Workouts.AssignedWorkout,
    Workouts.AssignedWorkoutAthlete,
    Workouts.Domain.WorkoutAuthoring,
    Workouts.Domain.WorkoutMaterializer,
    Workouts.ExerciseVariation,
    Workouts.MasterWorkout,
    Workouts.WorkoutExercise,
    Workouts.WorkoutSection
  }

  @workout_preloads [sections: [exercises: [variations: [:scale_level]]]]
  @assigned_workout_preloads [:athlete_links, master_workout: @workout_preloads]

  @impl true
  def create_workout(admin_id, params) do
    with normalized_params <- WorkoutAuthoring.normalize_structure(params),
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
            |> normalize_workout()

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
      {:ok, workout} -> {:ok, %{id: workout.id, status: to_string(workout.status)}}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
    end
  end

  @impl true
  def update_draft(id, params) do
    case Repo.get(MasterWorkout, id) do
      nil ->
        {:error, :not_found}

      workout ->
        draft_data =
          params
          |> Map.get(:draft_data, Map.get(params, "draft_data", params))
          |> stringify_keys_deep()

        top_level =
          draft_data
          |> extract_top_level_draft_fields()
          |> Map.put(:draft_data, draft_data)

        workout
        |> MasterWorkout.update_draft_changeset(top_level)
        |> Repo.update()
        |> case do
          {:ok, updated} -> {:ok, %{id: updated.id, status: to_string(updated.status)}}
          {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def delete_workout(id) do
    case Repo.get(MasterWorkout, id) do
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
    case Repo.get(MasterWorkout, id) do
      nil ->
        {:error, :not_found}

      %MasterWorkout{status: :published} ->
        {:error, :already_published}

      workout ->
        draft_data = workout.draft_data || %{}

        merged_params =
          draft_data
          |> Map.merge(stringify_keys_deep(params))
          |> WorkoutAuthoring.normalize_structure()
          |> stringify_keys_deep()

        sections = Map.get(merged_params, "sections") || Map.get(merged_params, :sections) || []

        all_exercises_empty =
          sections == [] or
            Enum.all?(sections, fn s ->
              (s["exercises"] || s[:exercises] || []) == []
            end)

        if all_exercises_empty do
          {:error, :no_sections}
        else
          with {:ok, params_with_levels} <- attach_scale_level_ids(merged_params) do
            Multi.new()
            |> Multi.update(:workout, MasterWorkout.publish_changeset(workout, merged_params))
            |> Multi.delete_all(:old_sections, Ecto.assoc(workout, :sections))
            |> Multi.run(:new_sections, fn _repo, %{workout: published_workout} ->
              insert_sections(published_workout.id, params_with_levels)
            end)
            |> Repo.transaction()
            |> case do
              {:ok, %{workout: published}} ->
                published =
                  published
                  |> Repo.preload(@workout_preloads)
                  |> normalize_workout()

                {:ok, published}

              {:error, _step, %Ecto.Changeset{} = changeset, _changes} ->
                {:error, changeset}
            end
          end
        end
    end
  end

  @impl true
  def get_workout(id) do
    MasterWorkout
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
    case Repo.get(MasterWorkout, id) do
      nil ->
        nil

      %MasterWorkout{} = workout ->
        draft_sections =
          workout.draft_data
          |> extract_sections_from_draft()

        base = %{
          id: workout.id,
          title: workout.title,
          type: workout.type && to_string(workout.type),
          status: to_string(workout.status),
          draft_data: workout.draft_data,
          sections: draft_sections
        }

        if workout.status == :published do
          workout
          |> Repo.preload(@workout_preloads)
          |> normalize_workout()
          |> Map.put(:draft_data, workout.draft_data)
        else
          base
        end
    end
  end

  @impl true
  def list_workouts do
    MasterWorkout
    |> order_by([workout], desc: workout.inserted_at)
    |> Repo.all()
    |> Repo.preload(@workout_preloads)
    |> Enum.map(fn workout ->
      workout
      |> normalize_workout()
      |> Map.update!(:sections, &summarize_sections_for_list/1)
    end)
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

    case Repo.get(AssignedWorkout, id) do
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
    case Repo.get(AssignedWorkout, id) do
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
          assignment.scheduled_for >= ^start_date and
          assignment.scheduled_for <= ^end_date
      )
      |> order_by([assignment, _link], asc: assignment.scheduled_for, asc: assignment.inserted_at)
      |> Repo.all()
      |> Repo.preload(@assigned_workout_preloads)
      |> Enum.map(&normalize_assignment_for_athlete(&1, athlete_id))

    workout_ids =
      normalized
      |> Enum.map(& &1.master_workout_id)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    completion_map = fetch_latest_completed_executions(athlete_id, workout_ids)

    Enum.map(normalized, fn assignment ->
      case Map.get(completion_map, assignment.master_workout_id) do
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
      Enum.map(assignment.athlete_links, fn link ->
        %{
          user_id: link.athlete_id,
          scheduled_for: assignment.scheduled_for,
          assigned_workout_id: assignment.id
        }
      end)
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
      sync_athlete_links(repo, assignment.id, athlete_ids)
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

  defp normalize_workout(%MasterWorkout{} = workout) do
    sections = normalize_sections(workout.sections)

    normalized = %{
      id: workout.id,
      title: workout.title,
      type: workout.type |> to_string(),
      status: workout.status |> to_string(),
      created_by_id: workout.created_by_id,
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
    |> Map.put(:my_athlete_status, my_status)
  end

  defp fetch_latest_completed_executions(_athlete_id, []), do: %{}

  defp fetch_latest_completed_executions(athlete_id, workout_ids) do
    WorkoutExecution
    |> where(
      [e],
      e.user_id == ^athlete_id and
        e.master_workout_id in ^workout_ids and
        not is_nil(e.completed_at_utc)
    )
    |> order_by([e], desc: e.completed_at_utc)
    |> select([e], %{master_workout_id: e.master_workout_id, section_scores: e.section_scores})
    |> Repo.all()
    |> Enum.group_by(& &1.master_workout_id)
    |> Map.new(fn {id, [first | _rest]} -> {id, first} end)
  end

  defp normalize_exercise(%WorkoutExercise{} = exercise) do
    %{
      id: exercise.id,
      name: exercise.name,
      sets: exercise.sets,
      prescription_value: exercise.prescription_value,
      prescription_unit: exercise.prescription_unit && to_string(exercise.prescription_unit),
      load_value: exercise.load_value,
      load_mode: exercise.load_mode && to_string(exercise.load_mode),
      superset_group_id: exercise.superset_group_id,
      hr_zone: exercise.hr_zone,
      tempo: exercise.tempo,
      rest_seconds: exercise.rest_seconds,
      cluster_rest_seconds: exercise.cluster_rest_seconds,
      rest_pause_seconds: exercise.rest_pause_seconds,
      pacing: exercise.pacing,
      interval_assignment: exercise.interval_assignment,
      order: exercise.order,
      variations:
        exercise.variations
        |> Enum.sort_by(&{&1.scale_level.sort_order || 0, &1.scale_level.slug})
        |> Enum.map(&normalize_variation/1)
    }
  end

  defp normalize_base_exercise(%WorkoutExercise{} = exercise) do
    %{
      id: exercise.id,
      name: exercise.name,
      sets: exercise.sets,
      prescription_value: exercise.prescription_value,
      prescription_unit: exercise.prescription_unit && to_string(exercise.prescription_unit),
      load_value: exercise.load_value,
      load_mode: exercise.load_mode && to_string(exercise.load_mode),
      superset_group_id: exercise.superset_group_id,
      hr_zone: exercise.hr_zone,
      tempo: exercise.tempo,
      rest_seconds: exercise.rest_seconds,
      cluster_rest_seconds: exercise.cluster_rest_seconds,
      rest_pause_seconds: exercise.rest_pause_seconds,
      pacing: exercise.pacing,
      interval_assignment: exercise.interval_assignment,
      order: exercise.order
    }
  end

  defp normalize_variation(%ExerciseVariation{} = variation) do
    %{
      id: variation.id,
      exercise_name_override: variation.exercise_name_override,
      sets: variation.sets,
      prescription_value: variation.prescription_value,
      prescription_unit: variation.prescription_unit && to_string(variation.prescription_unit),
      load_value: variation.load_value,
      load_mode: variation.load_mode && to_string(variation.load_mode),
      excluded: variation.excluded,
      scale_level: normalize_scale_level(variation.scale_level)
    }
  end

  defp insert_sections(workout_id, params) do
    sections = Map.get(params, :sections) || Map.get(params, "sections") || []

    insert_sections(workout_id, sections, nil)
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
  end

  defp extract_top_level_draft_fields(_draft_data), do: %{}

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
      type: workout.type |> to_string(),
      sections: normalize_sections(workout.sections)
    }
  end

  defp normalize_sections(sections, opts \\ []) do
    exercise_mapper = Keyword.get(opts, :exercise_mapper, &normalize_exercise/1)

    sections
    |> Enum.group_by(& &1.parent_section_id)
    |> flatten_sections(nil, nil, exercise_mapper)
  end

  defp flatten_sections(
         grouped_sections,
         parent_section_id,
         inherited_timer_config,
         exercise_mapper
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
        order: section.order,
        scoreable: section.scoreable,
        score_config: section.score_config,
        timer_config: effective_timer_config,
        exercises:
          section.exercises
          |> Enum.sort_by(& &1.order)
          |> Enum.map(exercise_mapper)
      }

      [
        normalized_section
        | flatten_sections(grouped_sections, section.id, effective_timer_config, exercise_mapper)
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

  defp sync_athlete_links(repo, assignment_id, athlete_ids) do
    existing_athlete_ids =
      repo.all(
        from link in AssignedWorkoutAthlete,
          where: link.assigned_workout_id == ^assignment_id,
          select: link.athlete_id
      )

    ids_to_remove = existing_athlete_ids -- athlete_ids

    if ids_to_remove != [] do
      repo.delete_all(
        from link in AssignedWorkoutAthlete,
          where: link.assigned_workout_id == ^assignment_id and link.athlete_id in ^ids_to_remove
      )
    end

    (athlete_ids -- existing_athlete_ids)
    |> Enum.reduce_while({:ok, []}, fn athlete_id, {:ok, acc} ->
      case %AssignedWorkoutAthlete{}
           |> AssignedWorkoutAthlete.changeset(%{
             assigned_workout_id: assignment_id,
             athlete_id: athlete_id
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
      sync_athlete_links(repo, assignment.id, merged_athlete_ids)
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
      "type" => workout.type && to_string(workout.type),
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
      "sets" => exercise.sets,
      "prescription_value" => exercise.prescription_value,
      "prescription_unit" => exercise.prescription_unit && to_string(exercise.prescription_unit),
      "load_value" => exercise.load_value,
      "load_mode" => exercise.load_mode && to_string(exercise.load_mode),
      "superset_group_id" => exercise.superset_group_id,
      "hr_zone" => exercise.hr_zone,
      "tempo" => exercise.tempo,
      "rest_seconds" => exercise.rest_seconds,
      "cluster_rest_seconds" => exercise.cluster_rest_seconds,
      "rest_pause_seconds" => exercise.rest_pause_seconds,
      "pacing" => exercise.pacing,
      "interval_assignment" => exercise.interval_assignment,
      "variations" => Enum.map(exercise.variations, &draft_variation_from_db/1)
    }
  end

  defp draft_variation_from_db(%ExerciseVariation{} = variation) do
    %{
      "id" => variation.id,
      "scale_level_slug" => variation.scale_level.slug,
      "exercise_name_override" => variation.exercise_name_override,
      "sets" => variation.sets,
      "prescription_value" => variation.prescription_value,
      "prescription_unit" =>
        variation.prescription_unit && to_string(variation.prescription_unit),
      "load_value" => variation.load_value,
      "load_mode" => variation.load_mode && to_string(variation.load_mode),
      "excluded" => variation.excluded
    }
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
            case Repo.get(AssignedWorkout, assignment_id) do
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
    case Repo.get(MasterWorkout, id) do
      nil ->
        {:error, :not_found}

      %MasterWorkout{status: :draft} ->
        {:error, :not_published}

      %MasterWorkout{status: :published} = workout ->
        workout_with_sections = Repo.preload(workout, @workout_preloads)
        draft_data = reconstruct_draft_data(workout_with_sections)

        case workout
             |> Ecto.Changeset.change(status: :draft, draft_data: draft_data)
             |> Repo.update() do
          {:ok, reopened} -> {:ok, %{id: reopened.id, status: "draft"}}
          {:error, changeset} -> {:error, changeset}
        end
    end
  end

  @impl true
  def get_assigned_workout(id) do
    case Repo.get(AssignedWorkout, id) do
      nil ->
        nil

      %AssignedWorkout{} = assignment ->
        assignment = Repo.preload(assignment, :athlete_links)

        %{
          id: assignment.id,
          athlete_ids: Enum.map(assignment.athlete_links, & &1.athlete_id),
          scheduled_for: assignment.scheduled_for
        }
    end
  end

  @impl true
  def duplicate_workout(id, title_suffix) do
    case Repo.get(MasterWorkout, id) do
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
          draft_data: draft_data
        }

        case %MasterWorkout{} |> MasterWorkout.draft_changeset(params) |> Repo.insert() do
          {:ok, new_workout} -> {:ok, %{id: new_workout.id, status: "draft", title: title}}
          {:error, changeset} -> {:error, changeset}
        end
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

  @impl true
  def substitute_assignment_workout(assignment_id, new_workout_id) do
    case Repo.get(AssignedWorkout, assignment_id) do
      nil ->
        {:error, :not_found}

      %AssignedWorkout{} = assignment ->
        case Repo.get(MasterWorkout, new_workout_id) do
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

  @impl true
  def get_assignment_with_auth(assignment_id, actor) do
    case AssignedWorkout
         |> Repo.get(assignment_id)
         |> Repo.preload(:athlete_links) do
      nil ->
        {:error, :not_found}

      %AssignedWorkout{} = assignment ->
        cond do
          actor.role == :admin ->
            {:ok, assignment}

          Enum.any?(assignment.athlete_links, &(&1.athlete_id == actor.id)) ->
            {:ok, assignment}

          true ->
            {:error, :forbidden}
        end
    end
  end

  @impl true
  def list_assignment_messages(assignment_id) do
    alias MilosTraining.Workouts.AssignmentMessage

    AssignmentMessage
    |> where([m], m.assigned_workout_id == ^assignment_id)
    |> order_by([m], asc: m.inserted_at)
    |> Repo.all()
    |> Enum.map(&normalize_assignment_message/1)
  end

  @impl true
  def create_assignment_message(params) do
    alias MilosTraining.Workouts.AssignmentMessage

    case AssignmentMessage.changeset(%AssignmentMessage{}, params) |> Repo.insert() do
      {:ok, message} -> {:ok, normalize_assignment_message(message)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp normalize_assignment_message(message) do
    %{
      id: message.id,
      assigned_workout_id: message.assigned_workout_id,
      sender_id: message.sender_id,
      sender_nickname: message.sender_nickname,
      body: message.body,
      inserted_at: message.inserted_at
    }
  end
end
