defmodule Palee.Application.AuthorizeTrainingLogSource do
  @moduledoc """
  Resolves the trusted source of a standalone training-log entry (ADR-118).

  Every branch derives the source facts (workout, booking, title) from the
  owning context's public API inside the caller's tenant context; nothing
  besides the source type and reference id is taken from the client.

    * `class` - a scheduled class the member attended or held an approved
      booking for, once it has started (Scheduling)
    * `assigned_workout` - an assignment that belongs to the athlete and was
      not rejected (Workouts)
    * `library_workout` - a published workout in the tenant, for the roles
      that may self-select workouts (mirrors ADR-029's self-selection rule)
    * `freeform` - no reference at all
  """

  alias Palee.{Execution, Scheduling, Workouts}

  @self_selection_roles [:owner, :admin, :coach, :member]

  def call(context, user_id, source_type, reference_id, %DateTime{} = now) do
    case {source_type, blank_to_nil(reference_id)} do
      {"freeform", nil} -> {:ok, %{source_type: "freeform", source_reference_id: nil}}
      {"freeform", _reference} -> {:error, :invalid_training_log_source}
      {_type, nil} -> {:error, :invalid_training_log_source}
      {"class", id} -> authorize_class(context, user_id, id, now)
      {"assigned_workout", id} -> authorize_assignment(context, user_id, id)
      {"library_workout", id} -> authorize_library_workout(context, id)
      _unknown -> {:error, :invalid_training_log_source}
    end
  end

  defp authorize_class(context, user_id, slot_id, now) do
    with {:ok, slot_id} <- uuid(slot_id),
         slot <- Scheduling.get_slot(context, slot_id),
         {:ok, booking_id} <-
           Execution.authorize_training_log_class(
             %{
               slot: slot,
               booking: Scheduling.get_approved_booking_for_class(context, user_id, slot_id),
               attendance: Scheduling.get_attendance_for_user_class(context, user_id, slot_id)
             },
             now
           ) do
      workout = slot.master_workout_id && Workouts.get_workout(context, slot.master_workout_id)

      {:ok,
       %{
         source_type: "class",
         source_reference_id: slot.id,
         booking_id: booking_id,
         master_workout_id: workout && workout.id,
         workout: workout,
         title: class_title(slot, workout),
         workout_type: workout && workout.type
       }}
    end
  end

  defp authorize_assignment(context, user_id, assignment_id) do
    with {:ok, assignment_id} <- uuid(assignment_id) do
      case Workouts.get_assignment_execution_access(context, assignment_id, user_id) do
        %{athlete_status: status, master_workout_id: workout_id}
        when status in [nil, "accepted"] ->
          workout_source(context, "assigned_workout", assignment_id, workout_id)

        %{} ->
          {:error, :training_log_source_forbidden}

        _missing ->
          {:error, :not_found}
      end
    end
  end

  defp authorize_library_workout(%{role: role} = context, workout_id)
       when role in @self_selection_roles do
    with {:ok, workout_id} <- uuid(workout_id) do
      workout_source(context, "library_workout", workout_id, workout_id)
    end
  end

  defp authorize_library_workout(_context, _workout_id),
    do: {:error, :training_log_source_forbidden}

  defp workout_source(context, source_type, reference_id, workout_id) do
    case workout_id && Workouts.get_workout(context, workout_id) do
      %{id: id, title: title} = workout ->
        {:ok,
         %{
           source_type: source_type,
           source_reference_id: reference_id,
           master_workout_id: id,
           workout: workout,
           title: title || "Workout",
           workout_type: workout[:type]
         }}

      _missing ->
        {:error, :not_found}
    end
  end

  defp class_title(slot, workout) do
    slot[:name] || (slot[:class_type] && slot.class_type.name) || (workout && workout.title) ||
      "Class"
  end

  defp uuid(value) do
    case Ecto.UUID.cast(value) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end

  defp blank_to_nil(value) when value in [nil, ""], do: nil
  defp blank_to_nil(value), do: value
end
