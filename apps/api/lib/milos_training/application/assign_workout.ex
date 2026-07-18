defmodule MilosTraining.Application.AssignWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Finance, Identity, Notifications, Workouts}

  def call(params) do
    athlete_ids =
      params
      |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
      |> List.wrap()
      |> Enum.uniq()

    athletes = Identity.list_by_ids(athlete_ids)

    if valid_athletes?(athlete_ids, athletes) do
      delivery_id = Ecto.UUID.generate()

      with {:ok, reservations} <- reserve_touchpoints(athletes, delivery_id),
           {:ok, assignment} <- create_assignment(params, reservations),
           :ok <- finalize_touchpoints(reservations, assignment, delivery_id) do
        broadcast_assignment_refresh(assignment)
        dispatch_assignment_notification(assignment)
        {:ok, assignment}
      end
    else
      {:error, :invalid_athletes}
    end
  end

  defp reserve_touchpoints(athletes, delivery_id) do
    Enum.reduce_while(athletes, {:ok, []}, fn athlete, {:ok, reservations} ->
      request = %{
        channel: :personal_programming,
        capability: :receive_coaching_touchpoints,
        allowance: :coaching_touchpoints,
        quantity: 1,
        occurred_on: Date.utc_today(),
        source_context: "workouts",
        source_id: delivery_id,
        idempotency_key: "programming-delivery:#{delivery_id}:#{athlete.id}",
        metadata: %{"kind" => "programming_delivery"}
      }

      case Finance.reserve_entitlement(athlete.id, request) do
        {:ok, reservation} ->
          {:cont, {:ok, [{athlete.id, reservation} | reservations]}}

        error ->
          release_touchpoints(reservations, "Assignment entitlement reservation failed")
          {:halt, error}
      end
    end)
  end

  defp create_assignment(params, reservations) do
    case Workouts.assign_workout(params) do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, reason} ->
        release_touchpoints(reservations, "Workout assignment creation failed")
        {:error, reason}
    end
  end

  defp finalize_touchpoints(reservations, assignment, delivery_id) do
    Enum.reduce_while(reservations, :ok, fn
      {_athlete_id, %{id: nil}}, :ok ->
        {:cont, :ok}

      {athlete_id, %{id: reservation_id}}, :ok ->
        case Finance.finalize_entitlement(reservation_id, %{
               source_id: assignment.id,
               reason: "Programming delivered",
               idempotency_key: "programming-delivery-finalized:#{delivery_id}:#{athlete_id}",
               metadata: %{"assignment_id" => assignment.id}
             }) do
          {:ok, _entry} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
    end)
  end

  defp release_touchpoints(reservations, reason) do
    Enum.each(reservations, fn
      {_athlete_id, %{id: nil}} ->
        :ok

      {_athlete_id, %{id: reservation_id}} ->
        Finance.release_entitlement(reservation_id, %{
          reason: reason,
          idempotency_key: "programming-delivery-release:#{reservation_id}"
        })
    end)

    :ok
  end

  defp valid_athletes?(athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id)) and
      Enum.all?(athletes, &(&1.role == :athlete))
  end

  defp broadcast_assignment_refresh(assignment) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_created",
      payload: %{assignment_id: assignment.id}
    )
  end

  defp dispatch_assignment_notification(assignment) do
    workout = Map.get(assignment, :workout) || %{}

    Notifications.dispatch_event(:workout_assigned, %{
      assignment_id: assignment.id,
      athlete_ids: Map.get(assignment, :athlete_ids, []) || [],
      workout_title: Map.get(workout, :title) || Map.get(workout, "title"),
      scheduled_for: assignment.scheduled_for,
      notification_batch_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    :ok
  end
end
