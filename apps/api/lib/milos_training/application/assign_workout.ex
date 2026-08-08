defmodule MilosTraining.Application.AssignWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Finance, Identity, Notifications, Organizations, Workouts}

  def call(context, params) do
    with {:ok, athletes} <- fetch_tenant_athletes(context, athlete_ids(params)) do
      do_assign(context, params, athletes)
    end
  end

  def call(_params), do: {:error, :organization_context_required}

  defp do_assign(context, params, athletes) do
    athlete_ids =
      params
      |> athlete_ids()

    if valid_athletes?(context, athlete_ids, athletes) do
      delivery_id = Ecto.UUID.generate()

      with {:ok, reservations} <- reserve_touchpoints(context, athletes, delivery_id),
           {:ok, assignment} <- create_assignment(context, params, reservations),
           :ok <- finalize_touchpoints(context, reservations, assignment, delivery_id) do
        broadcast_assignment_refresh(context, assignment)
        dispatch_assignment_notification(context, assignment)
        {:ok, assignment}
      end
    else
      {:error, :invalid_athletes}
    end
  end

  defp athlete_ids(params) do
    params
    |> Map.get(:athlete_ids, Map.get(params, "athlete_ids", []))
    |> List.wrap()
    |> Enum.uniq()
  end

  defp fetch_tenant_athletes(%{organization_id: organization_id}, athlete_ids) do
    memberships_by_user =
      athlete_ids
      |> Map.new(fn user_id ->
        membership =
          user_id
          |> Organizations.list_memberships()
          |> Enum.find(fn %{membership: membership, organization: organization} ->
            organization.id == organization_id and membership.role == :athlete
          end)

        {user_id, membership}
      end)

    if Enum.all?(athlete_ids, &Map.has_key?(memberships_by_user, &1)) and
         Enum.all?(memberships_by_user, fn {_user_id, membership} -> not is_nil(membership) end) do
      {:ok, Identity.list_by_ids(athlete_ids)}
    else
      {:error, :invalid_athletes}
    end
  end

  defp fetch_tenant_athletes(_context, _athlete_ids), do: {:error, :organization_context_required}

  defp reserve_touchpoints(context, athletes, delivery_id) do
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

      case reserve_entitlement(context, athlete.id, request) do
        {:ok, reservation} ->
          {:cont, {:ok, [{athlete.id, reservation} | reservations]}}

        error ->
          release_touchpoints(context, reservations, "Assignment entitlement reservation failed")
          {:halt, error}
      end
    end)
  end

  defp create_assignment(context, params, reservations) do
    case assign_workout(context, params) do
      {:ok, assignment} ->
        {:ok, assignment}

      {:error, reason} ->
        release_touchpoints(context, reservations, "Workout assignment creation failed")
        {:error, reason}
    end
  end

  defp finalize_touchpoints(context, reservations, assignment, delivery_id) do
    Enum.reduce_while(reservations, :ok, fn
      {_athlete_id, %{id: nil}}, :ok ->
        {:cont, :ok}

      {athlete_id, %{id: reservation_id}}, :ok ->
        case finalize_entitlement(context, reservation_id, %{
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

  defp release_touchpoints(context, reservations, reason) do
    Enum.each(reservations, fn
      {_athlete_id, %{id: nil}} ->
        :ok

      {_athlete_id, %{id: reservation_id}} ->
        release_entitlement(context, reservation_id, %{
          reason: reason,
          idempotency_key: "programming-delivery-release:#{reservation_id}"
        })
    end)

    :ok
  end

  defp valid_athletes?(_context, athlete_ids, athletes) do
    MapSet.new(athlete_ids) == MapSet.new(Enum.map(athletes, & &1.id))
  end

  defp broadcast_assignment_refresh(%{organization_id: organization_id}, assignment) do
    admin_ids = Organizations.list_staff_user_ids(organization_id)

    BroadcastUserSync.for_users(
      (Map.get(assignment, :athlete_ids, []) || []) ++ admin_ids,
      ["assigned_workouts"],
      reason: "assignment_created",
      payload: %{assignment_id: assignment.id}
    )
  end

  defp dispatch_assignment_notification(context, assignment) do
    workout = Map.get(assignment, :workout) || %{}

    Notifications.dispatch_event(:workout_assigned, %{
      organization_id: context.organization_id,
      assignment_id: assignment.id,
      athlete_ids: Map.get(assignment, :athlete_ids, []) || [],
      workout_title: Map.get(workout, :title) || Map.get(workout, "title"),
      scheduled_for: assignment.scheduled_for,
      notification_batch_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })

    :ok
  end

  defp reserve_entitlement(context, user_id, request),
    do: Finance.reserve_entitlement(context, user_id, request)

  defp finalize_entitlement(context, reservation_id, params),
    do: Finance.finalize_entitlement(context, reservation_id, params)

  defp release_entitlement(context, reservation_id, params),
    do: Finance.release_entitlement(context, reservation_id, params)

  defp assign_workout(context, params), do: Workouts.assign_workout(context, params)
end
