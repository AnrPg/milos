defmodule MilosTraining.Application.GetOrCreateMessagingThread do
  @moduledoc """
  Authorizes a messaging context through its owning bounded context before
  asking Messaging to atomically create or return the thread.
  """

  alias MilosTraining.{Identity, Messaging, Scheduling, Workouts}

  def call(%{id: actor_id}, %{context_type: :direct, participant_id: actor_id}),
    do: {:error, :self_conversation}

  def call(actor, %{context_type: :direct, participant_id: participant_id}) do
    with %{} <- Identity.find_by_id(participant_id) || {:error, :not_found} do
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: actor.id,
        participant_id: participant_id
      })
    end
  end

  def call(actor, %{context_type: :assignment, context_id: assignment_id}) do
    with {:ok, assignment} <- Workouts.get_assignment_with_auth(assignment_id, actor) do
      participant_ids =
        assignment.athlete_links
        |> Enum.reject(&(&1.athlete_status == :archived))
        |> Enum.map(& &1.athlete_id)
        |> add_admins_and_actor(actor.id)

      Messaging.get_or_create_thread(%{
        context_type: :assignment,
        context_id: assignment_id,
        actor_id: actor.id,
        participants: participant_ids
      })
    end
  end

  def call(actor, %{context_type: :class_slot, context_id: slot_id}) do
    with %{} = slot <- Scheduling.get_slot(slot_id) || {:error, :not_found},
         :ok <- authorize_class_slot(actor, slot_id) do
      participant_ids =
        slot
        |> Map.get(:bookings, [])
        |> Enum.filter(&(to_string(&1.status) == "approved"))
        |> Enum.map(& &1.user_id)
        |> add_admins_and_actor(actor.id)

      Messaging.get_or_create_thread(%{
        context_type: :class_slot,
        context_id: slot_id,
        actor_id: actor.id,
        participants: participant_ids
      })
    end
  end

  def call(_actor, _params), do: {:error, :bad_request}

  defp authorize_class_slot(%{role: :admin}, _slot_id), do: :ok

  defp authorize_class_slot(%{id: actor_id}, slot_id) do
    if Scheduling.get_approved_booking_for_class(actor_id, slot_id) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp add_admins_and_actor(participant_ids, actor_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)
    Enum.uniq([actor_id | participant_ids ++ admin_ids])
  end
end
