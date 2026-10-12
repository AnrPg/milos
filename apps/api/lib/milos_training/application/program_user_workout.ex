defmodule MilosTraining.Application.ProgramUserWorkout do
  alias MilosTraining.Application.{AssignWorkout, FileWorkoutCopy, WorkoutLibraryFolders}
  alias MilosTraining.{Identity, Organizations, Scheduling, Workouts}

  def call(context, _admin, user_id, params) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, role} <- tenant_role(context, user.id),
         :ok <- validate_target(context, role, user, params),
         {:ok, folder_id} <- target_folder_id(context, role, user, params),
         {:ok, workout} <- prepare_workout(context, role, folder_id, params),
         {:ok, association} <- associate(context, role, user, workout.id, params) do
      {:ok, %{workout: workout, association: association}}
    end
  end

  def call(_admin, _user_id, _params), do: {:error, :organization_context_required}

  defp validate_target(context, :member, %{id: member_id}, params) do
    with slot_id when is_binary(slot_id) <- value(params, :slot_id),
         {:ok, date} <- date(value(params, :scheduled_for)),
         start_at = DateTime.new!(date, ~T[00:00:00], "Etc/UTC"),
         end_at = date |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC"),
         true <-
           Enum.any?(
             Scheduling.list_member_slots(context, member_id, start_at, end_at),
             &(&1.id == slot_id)
           ) do
      :ok
    else
      _ -> {:error, :slot_not_booked_by_member}
    end
  end

  defp validate_target(_context, :athlete, _user, _params), do: :ok
  defp validate_target(_context, _role, _user, _params), do: {:error, :unsupported_role}

  # Without an explicit folder the workout is filed automatically: in the
  # athlete's own folder, or in the class's Classes/<year>/<month>/<date> folder.
  defp target_folder_id(context, role, user, params) do
    case value(params, :folder_id) do
      folder_id when is_binary(folder_id) and folder_id != "" -> {:ok, folder_id}
      _automatic -> default_folder_id(context, role, user, params)
    end
  end

  defp default_folder_id(context, :athlete, user, _params) do
    with {:ok, folder} <- WorkoutLibraryFolders.athlete_folder(context, user),
         do: {:ok, folder.id}
  end

  defp default_folder_id(context, :member, _user, params) do
    with %{scheduled_at: scheduled_at} <-
           Scheduling.get_slot(context, value(params, :slot_id)) || {:error, :not_found},
         {:ok, folder} <- WorkoutLibraryFolders.class_day_folder(context, scheduled_at) do
      {:ok, folder.id}
    end
  end

  defp prepare_workout(context, role, folder_id, params) do
    source_id = value(params, :master_workout_id)
    copy? = value(params, :copy_source) != false

    if copy? do
      # Classes on the same day share one filed copy; athletes each get their own.
      FileWorkoutCopy.ensure_in_folder(context, source_id, folder_id, reuse_copy: role == :member)
    else
      with %{} = workout <-
             Workouts.get_workout(context, source_id) || {:error, :workout_not_found},
           {:ok, _metadata} <-
             Workouts.update_library_metadata(context, source_id, %{folder_id: folder_id}) do
        {:ok, Map.put(workout, :folder_id, folder_id)}
      end
    end
  end

  defp associate(context, :athlete, %{id: athlete_id}, workout_id, params) do
    AssignWorkout.call(context, %{
      master_workout_id: workout_id,
      athlete_ids: [athlete_id],
      scheduled_for: value(params, :scheduled_for),
      admin_notes: value(params, :admin_notes)
    })
  end

  defp associate(context, :member, _user, workout_id, params) do
    case value(params, :slot_id) do
      nil -> {:error, :slot_required}
      slot_id -> Scheduling.substitute_slot_workout(context, slot_id, workout_id)
    end
  end

  defp associate(_context, _role, _user, _workout_id, _params), do: {:error, :unsupported_role}

  defp tenant_role(%{organization_id: organization_id}, user_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.find(fn %{membership: membership, organization: organization} ->
      organization.id == organization_id and membership.status == :active
    end)
    |> case do
      %{membership: %{role: role}} -> {:ok, role}
      _missing -> {:error, :unsupported_role}
    end
  end

  defp tenant_role(_context, _user_id), do: {:error, :organization_context_required}

  defp date(%Date{} = date), do: {:ok, date}
  defp date(value) when is_binary(value), do: Date.from_iso8601(value)
  defp date(_value), do: {:error, :invalid_date}

  defp value(map, key) do
    case Map.fetch(map, key) do
      {:ok, value} -> value
      :error -> Map.get(map, Atom.to_string(key))
    end
  end
end
