defmodule MilosTraining.Application.AuthorizeWorkoutExecutionSource do
  @moduledoc """
  Resolves the trusted source - and the owning organization - for a workout
  execution.

  F-03: every branch must return a server-derived `organization_id`. The
  `self_selected` and `class_booking` branches previously returned none, so the
  client-supplied value in `StartExecution` passed through unchecked and an
  execution could be attributed to any organization the caller named.
  """

  alias MilosTraining.{Organizations, Scheduling, Workouts}
  alias MilosTraining.Workouts.WorkoutStore

  def call(actor, workout_id, source, source_reference_id) do
    case normalize_source(source) do
      "self_selected" -> authorize_self_selected(actor, workout_id, source_reference_id)
      "assigned" -> authorize_assignment(actor, workout_id, source_reference_id)
      "class_booking" -> authorize_booking(actor, workout_id, source_reference_id)
      _source -> {:error, :invalid_execution_source}
    end
  end

  defp authorize_self_selected(actor, workout_id, reference) when reference in [nil, ""] do
    # The organization comes from the workout being executed, and the actor must
    # actually be an active member of it. Nothing here is client-supplied.
    with organization_id when is_binary(organization_id) <-
           WorkoutStore.workout_organization_id(workout_id),
         true <- may_self_select?(actor, organization_id) do
      {:ok,
       %{
         source: "self_selected",
         source_reference_id: nil,
         organization_id: organization_id
       }}
    else
      _denied -> {:error, :execution_source_forbidden}
    end
  end

  defp authorize_self_selected(_actor, _workout_id, _source_reference_id),
    do: {:error, :execution_source_forbidden}

  # Self-selection is a member-side capability: athletes train from what their
  # coach assigned. That rule predates this fix and is preserved - but it is now
  # read from the membership in the workout's organization rather than the
  # account-wide role (F-29), so the same person can be a member at one gym and
  # an athlete at another.
  @self_selection_roles [:owner, :admin, :coach, :member]

  defp may_self_select?(%{id: user_id}, organization_id) do
    user_id
    |> Organizations.list_memberships()
    |> Enum.any?(fn %{membership: membership, organization: organization} ->
      organization.id == organization_id and membership.status == :active and
        membership.role in @self_selection_roles
    end)
  end

  defp may_self_select?(_actor, _organization_id), do: false

  defp authorize_assignment(%{id: athlete_id, role: :athlete}, workout_id, assignment_id)
       when is_binary(assignment_id) do
    case Workouts.get_assignment_execution_access(assignment_id, athlete_id) do
      %{master_workout_id: ^workout_id, athlete_status: status} = access
      when status in [nil, "accepted"] ->
        {:ok,
         %{
           source: "assigned",
           source_reference_id: assignment_id,
           organization_id: access.organization_id
         }}

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

  defp authorize_booking(%{id: user_id}, workout_id, booking_id) when is_binary(booking_id) do
    case Scheduling.get_booking_execution_access(booking_id, user_id) do
      %{master_workout_id: ^workout_id, status: "approved"} = access ->
        {:ok,
         %{
           source: "class_booking",
           source_reference_id: booking_id,
           organization_id: access.organization_id
         }}

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
