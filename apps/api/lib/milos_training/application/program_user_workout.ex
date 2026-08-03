defmodule MilosTraining.Application.ProgramUserWorkout do
  alias MilosTraining.Application.{AssignWorkout, DuplicateWorkout}
  alias MilosTraining.{Identity, Scheduling, Workouts}

  def call(admin, user_id, params) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         :ok <- validate_target(user, params),
         {:ok, workout} <- prepare_workout(admin, user, params),
         {:ok, association} <- associate(user, workout.id, params) do
      {:ok, %{workout: workout, association: association}}
    end
  end

  defp validate_target(%{role: :member, id: member_id}, params) do
    with slot_id when is_binary(slot_id) <- value(params, :slot_id),
         {:ok, date} <- date(value(params, :scheduled_for)),
         start_at = DateTime.new!(date, ~T[00:00:00], "Etc/UTC"),
         end_at = date |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC"),
         true <-
           Enum.any?(
             Scheduling.list_member_slots(member_id, start_at, end_at),
             &(&1.id == slot_id)
           ) do
      :ok
    else
      _ -> {:error, :slot_not_booked_by_member}
    end
  end

  defp validate_target(%{role: :athlete}, _params), do: :ok
  defp validate_target(_user, _params), do: {:error, :unsupported_role}

  defp prepare_workout(_admin, user, params) do
    source_id = value(params, :master_workout_id)
    folder_id = value(params, :folder_id)
    copy? = value(params, :copy_source) != false

    if copy? do
      suffix = "(#{user.nickname} #{value(params, :scheduled_for)})"

      with {:ok, draft} <-
             DuplicateWorkout.call(source_id, folder_id: folder_id, title_suffix: suffix),
           {:ok, published} <- Workouts.publish_workout(draft.id, %{}) do
        {:ok, published}
      end
    else
      with %{} = workout <- Workouts.get_workout(source_id) || {:error, :workout_not_found},
           {:ok, _metadata} <-
             Workouts.update_library_metadata(source_id, %{folder_id: folder_id}) do
        {:ok, Map.put(workout, :folder_id, folder_id)}
      end
    end
  end

  defp associate(%{role: :athlete, id: athlete_id}, workout_id, params) do
    AssignWorkout.call(%{
      master_workout_id: workout_id,
      athlete_ids: [athlete_id],
      scheduled_for: value(params, :scheduled_for),
      admin_notes: value(params, :admin_notes)
    })
  end

  defp associate(%{role: :member}, workout_id, params) do
    case value(params, :slot_id) do
      nil -> {:error, :slot_required}
      slot_id -> Scheduling.substitute_slot_workout(slot_id, workout_id)
    end
  end

  defp associate(_user, _workout_id, _params), do: {:error, :unsupported_role}

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
