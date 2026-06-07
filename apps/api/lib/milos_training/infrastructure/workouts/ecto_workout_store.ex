defmodule MilosTraining.Infrastructure.Workouts.EctoWorkoutStore do
  @behaviour MilosTraining.Workouts.Ports.WorkoutStore

  import Ecto.Query

  alias Ecto.Multi

  alias MilosTraining.{
    Repo,
    ScaleLevel,
    Workouts.Domain.WorkoutAuthoring,
    Workouts.Domain.WorkoutMaterializer,
    Workouts.ExerciseVariation,
    Workouts.MasterWorkout,
    Workouts.WorkoutExercise,
    Workouts.WorkoutSection
  }

  @workout_preloads [sections: [exercises: [variations: [:scale_level]]]]

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
  def publish_workout(id, params) do
    case Repo.get(MasterWorkout, id) do
      nil ->
        {:error, :not_found}

      workout ->
        draft_data = workout.draft_data || %{}

        merged_params =
          draft_data
          |> Map.merge(stringify_keys_deep(params))
          |> WorkoutAuthoring.normalize_structure()
          |> stringify_keys_deep()

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
    |> Enum.map(&normalize_workout/1)
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
        Enum.each(removable, &repo.delete!/1)
        {:ok, :guarded}
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

    sections
    |> Enum.reduce_while({:ok, []}, fn section, {:ok, acc_sections} ->
      exercises = Map.get(section, :exercises) || Map.get(section, "exercises") || []

      case attach_exercise_scale_level_ids(exercises, scale_level_ids) do
        {:ok, updated_exercises} ->
          updated_section =
            section
            |> drop_key("exercises")
            |> drop_key(:exercises)
            |> Map.put(:exercises, updated_exercises)

          {:cont, {:ok, [updated_section | acc_sections]}}

        {:error, changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, updated_sections} ->
        {:ok, Map.put(params, :sections, Enum.reverse(updated_sections))}

      {:error, changeset} ->
        {:error, changeset}
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
    sections =
      workout.sections
      |> Enum.sort_by(& &1.order)
      |> Enum.map(&normalize_section/1)

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

  defp normalize_section(%WorkoutSection{} = section) do
    %{
      id: section.id,
      parent_section_id: section.parent_section_id,
      name: section.name,
      order: section.order,
      scoreable: section.scoreable,
      score_config: section.score_config,
      timer_config: section.timer_config,
      exercises:
        section.exercises
        |> Enum.sort_by(& &1.order)
        |> Enum.map(&normalize_exercise/1)
    }
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
        |> Enum.sort_by(& &1.scale_level.sort_order)
        |> Enum.map(&normalize_variation/1)
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

    Enum.reduce_while(sections, {:ok, []}, fn section_params, {:ok, acc_sections} ->
      exercises =
        Map.get(section_params, :exercises) || Map.get(section_params, "exercises") || []

      section_params =
        section_params
        |> drop_key(:exercises)
        |> drop_key("exercises")
        |> Map.put("master_workout_id", workout_id)

      case %WorkoutSection{}
           |> WorkoutSection.persist_changeset(section_params)
           |> Repo.insert() do
        {:ok, section} ->
          case insert_exercises(section.id, exercises) do
            {:ok, _exercises} -> {:cont, {:ok, [section | acc_sections]}}
            error -> {:halt, error}
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          {:halt, {:error, changeset}}
      end
    end)
    |> case do
      {:ok, sections} -> {:ok, Enum.reverse(sections)}
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

  defp blank?(value), do: is_nil(value) or String.trim(to_string(value)) == ""

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp drop_key(map, key) do
    if Map.has_key?(map, key), do: Map.delete(map, key), else: map
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
end
