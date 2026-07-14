defmodule MilosTraining.Application.AuthorizeWorkoutExecutionSource do
  alias MilosTraining.{Scheduling, Workouts}

  def call(actor, workout_id, source, source_reference_id) do
    case normalize_source(source) do
      "self_selected" -> authorize_self_selected(actor, source_reference_id)
      "assigned" -> authorize_assignment(actor, workout_id, source_reference_id)
      "class_booking" -> authorize_booking(actor, workout_id, source_reference_id)
      _source -> {:error, :invalid_execution_source}
    end
  end

  defp authorize_self_selected(%{role: role}, nil) when role in [:member, :admin],
    do: {:ok, %{source: "self_selected", source_reference_id: nil}}

  defp authorize_self_selected(%{role: role}, "") when role in [:member, :admin],
    do: {:ok, %{source: "self_selected", source_reference_id: nil}}

  defp authorize_self_selected(_actor, _source_reference_id),
    do: {:error, :execution_source_forbidden}

  defp authorize_assignment(%{id: athlete_id, role: :athlete}, workout_id, assignment_id)
       when is_binary(assignment_id) do
    case Workouts.get_assignment_execution_access(assignment_id, athlete_id) do
      %{master_workout_id: ^workout_id, athlete_status: status}
      when status in [nil, "accepted"] ->
        {:ok, %{source: "assigned", source_reference_id: assignment_id}}

      %{master_workout_id: ^workout_id, athlete_status: "rejected"} ->
        {:error, :execution_source_forbidden}

      %{} ->
        {:error, :execution_source_mismatch}

      nil ->
        {:error, :execution_source_forbidden}
    end
  end

  defp authorize_assignment(_actor, _workout_id, _assignment_id),
    do: {:error, :execution_source_forbidden}

  defp authorize_booking(%{id: user_id, role: role}, workout_id, booking_id)
       when role in [:member, :admin] and is_binary(booking_id) do
    case Scheduling.get_booking_execution_access(booking_id, user_id) do
      %{master_workout_id: ^workout_id, status: "approved"} ->
        {:ok, %{source: "class_booking", source_reference_id: booking_id}}

      %{master_workout_id: ^workout_id} ->
        {:error, :execution_source_forbidden}

      %{} ->
        {:error, :execution_source_mismatch}

      nil ->
        {:error, :execution_source_forbidden}
    end
  end

  defp authorize_booking(_actor, _workout_id, _booking_id),
    do: {:error, :execution_source_forbidden}

  defp normalize_source(source) when is_atom(source), do: Atom.to_string(source)
  defp normalize_source(source) when is_binary(source), do: source
  defp normalize_source(_source), do: nil
end
