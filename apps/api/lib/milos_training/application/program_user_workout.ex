defmodule MilosTraining.Application.ProgramUserWorkout do
  @moduledoc """
  Programs a workout for one user from the admin profile calendar (ADR-071).

  Athletes receive a personal assignment. Members (ADR-125) are programmed in
  one of three modes:

  - `class_workout` (default, ADR-071): the copy replaces the workout of a class
    the member booked - for every attendee.
  - `class_variant`: the copy becomes this member's own version of the booked
    class (an assignment linked to the slot); the class keeps its workout. The
    source defaults to the class's workout.
  - `personal`: the copy is assigned to the member without any class.

  Without an explicit folder, copies are filed automatically (ADR-136): athlete
  copies in `Athletes/<nickname>`, class workouts in the class's
  `Classes/<year>/<month>/<date>` folder, and a member's personal copies and
  class variants in `Variations for member/<nickname>` (still hidden from the
  shared library, ADR-125).

  The two member assignment modes require the explicit personal-programming
  grant, checked before the library copy is made so a denial leaves no orphan.
  """

  alias MilosTraining.Application.{
    AssignWorkout,
    AuthorizeMemberProgramming,
    DuplicateWorkout,
    FileWorkoutCopy,
    WorkoutLibraryFolders
  }

  alias MilosTraining.{Identity, Organizations, Scheduling, Workouts}
  alias MilosTraining.Workouts.Domain.AssignmentAudiencePolicy

  def call(context, _admin, user_id, params) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, role} <- tenant_role(context, user.id),
         {:ok, mode} <- programming_mode(role, params),
         :ok <- validate_target(context, mode, user, params),
         {:ok, params} <- resolve_source_workout(context, mode, params),
         {:ok, folder_id} <- target_folder_id(context, mode, user, params),
         {:ok, workout} <- prepare_workout(context, mode, user, folder_id, params),
         :ok <- keep_member_copy_personal(context, mode, workout, params),
         {:ok, association} <- associate(context, mode, user, workout.id, params) do
      {:ok, %{workout: workout, association: association, mode: to_string(mode)}}
    end
  end

  def call(_admin, _user_id, _params), do: {:error, :organization_context_required}

  defp programming_mode(:athlete, _params), do: {:ok, :athlete}

  defp programming_mode(:member, params),
    do: AssignmentAudiencePolicy.member_programming_mode(value(params, :mode))

  defp programming_mode(_role, _params), do: {:error, :unsupported_role}

  defp validate_target(_context, :athlete, _user, _params), do: :ok

  defp validate_target(context, :personal, %{id: member_id}, _params),
    do: AuthorizeMemberProgramming.call(context, [member_id])

  defp validate_target(context, :class_variant, %{id: member_id} = user, params) do
    with :ok <- validate_booked_slot(context, user, params) do
      AuthorizeMemberProgramming.call(context, [member_id])
    end
  end

  defp validate_target(context, :class_workout, user, params),
    do: validate_booked_slot(context, user, params)

  defp validate_booked_slot(context, %{id: member_id}, params) do
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

  # A member's version of a class starts from the class's own workout unless
  # the coach picked another source.
  defp resolve_source_workout(context, :class_variant, params) do
    case value(params, :master_workout_id) do
      id when is_binary(id) and id != "" ->
        {:ok, params}

      _missing ->
        case Scheduling.get_slot(context, value(params, :slot_id)) do
          %{master_workout_id: workout_id} when is_binary(workout_id) ->
            {:ok, Map.put(params, :master_workout_id, workout_id)}

          _ ->
            {:error, :workout_not_found}
        end
    end
  end

  defp resolve_source_workout(_context, _mode, params) do
    case value(params, :master_workout_id) do
      id when is_binary(id) and id != "" -> {:ok, params}
      _missing -> {:error, :workout_not_found}
    end
  end

  # Without an explicit folder the workout is filed automatically: in the
  # athlete's own folder, the class's Classes/<year>/<month>/<date> folder, or
  # the member's Variations for member/<nickname> folder.
  defp target_folder_id(context, mode, user, params) do
    case value(params, :folder_id) do
      folder_id when is_binary(folder_id) and folder_id != "" -> {:ok, folder_id}
      _automatic -> default_folder_id(context, mode, user, params)
    end
  end

  defp default_folder_id(context, :athlete, user, _params) do
    with {:ok, folder} <- WorkoutLibraryFolders.athlete_folder(context, user),
         do: {:ok, folder.id}
  end

  defp default_folder_id(context, :class_workout, _user, params) do
    with %{scheduled_at: scheduled_at} <-
           Scheduling.get_slot(context, value(params, :slot_id)) || {:error, :not_found},
         {:ok, folder} <- WorkoutLibraryFolders.class_day_folder(context, scheduled_at) do
      {:ok, folder.id}
    end
  end

  defp default_folder_id(context, _personal_mode, user, _params) do
    with {:ok, folder} <- WorkoutLibraryFolders.member_variation_folder(context, user),
         do: {:ok, folder.id}
  end

  # A member's personal copy is always a fresh copy, so hiding it from the
  # library (keep_member_copy_personal/4) never hides a shared workout.
  defp prepare_workout(context, mode, user, folder_id, params)
       when mode in [:personal, :class_variant] do
    if value(params, :copy_source) != false do
      source_id = value(params, :master_workout_id)
      suffix = "(#{user.nickname} #{value(params, :scheduled_for)})"

      with {:ok, draft} <-
             DuplicateWorkout.call(context, source_id,
               folder_id: folder_id,
               title_suffix: suffix
             ) do
        Workouts.publish_workout(context, draft.id, %{expected_source_revision: 0})
      end
    else
      file_original(context, folder_id, params)
    end
  end

  defp prepare_workout(context, mode, _user, folder_id, params) do
    if value(params, :copy_source) != false do
      # Classes on the same day share one filed copy; athletes each get their own.
      FileWorkoutCopy.ensure_in_folder(context, value(params, :master_workout_id), folder_id,
        reuse_copy: mode == :class_workout
      )
    else
      file_original(context, folder_id, params)
    end
  end

  defp file_original(context, folder_id, params) do
    source_id = value(params, :master_workout_id)

    with %{} = workout <-
           Workouts.get_workout(context, source_id) || {:error, :workout_not_found},
         {:ok, _metadata} <-
           Workouts.update_library_metadata(context, source_id, %{folder_id: folder_id}) do
      {:ok, Map.put(workout, :folder_id, folder_id)}
    end
  end

  # Owner decision (ADR-125): a copy made for one member's personalized
  # programming never appears in the shared workout library. Athlete copies and
  # the class-workout mode keep the ADR-071 behaviour.
  defp keep_member_copy_personal(context, mode, workout, params)
       when mode in [:personal, :class_variant] do
    if value(params, :copy_source) != false do
      case Workouts.update_library_metadata(context, workout.id, %{library_visibility: "personal"}) do
        {:ok, _metadata} -> :ok
        error -> error
      end
    else
      :ok
    end
  end

  defp keep_member_copy_personal(_context, _mode, _workout, _params), do: :ok

  defp associate(context, mode, %{id: assignee_id}, workout_id, params)
       when mode in [:athlete, :personal] do
    AssignWorkout.call(context, %{
      master_workout_id: workout_id,
      athlete_ids: [assignee_id],
      scheduled_for: value(params, :scheduled_for),
      instructions: value(params, :instructions)
    })
  end

  defp associate(context, :class_variant, %{id: member_id}, workout_id, params) do
    AssignWorkout.call(context, %{
      master_workout_id: workout_id,
      athlete_ids: [member_id],
      scheduled_for: value(params, :scheduled_for),
      instructions: value(params, :instructions),
      source_slot_id: value(params, :slot_id)
    })
  end

  defp associate(context, :class_workout, _user, workout_id, params) do
    case value(params, :slot_id) do
      nil -> {:error, :slot_required}
      slot_id -> Scheduling.substitute_slot_workout(context, slot_id, workout_id)
    end
  end

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
