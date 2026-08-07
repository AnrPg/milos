defmodule MilosTraining.Application.GetOrCreateMessagingThread do
  @moduledoc """
  Authorizes a messaging context through its owning bounded context before
  asking Messaging to atomically create or return the thread.
  """

  alias MilosTraining.{Identity, Messaging, Organizations, Scheduling, Workouts}

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
    with {:ok, assignment} <- authorize_assignment(actor, assignment_id) do
      participant_ids =
        assignment.athlete_links
        |> Enum.reject(&(&1.athlete_status == :archived))
        |> Enum.map(& &1.athlete_id)
        |> add_org_staff_and_actor(actor.id, assignment.organization_id)

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
         :ok <- authorize_class_slot(actor, slot) do
      participant_ids =
        slot
        |> Map.get(:bookings, [])
        |> Enum.filter(&(to_string(&1.status) == "approved"))
        |> Enum.map(& &1.user_id)
        |> add_org_staff_and_actor(actor.id, slot.organization_id)

      Messaging.get_or_create_thread(%{
        context_type: :class_slot,
        context_id: slot_id,
        actor_id: actor.id,
        participants: participant_ids
      })
    end
  end

  def call(_actor, _params), do: {:error, :bad_request}

  # Assignments belong to one organization; an actor is authorized either as
  # a (non-archived) participant on it, or as owner/admin/coach staff of that
  # same organization - never by the account's global role (that let any
  # platform-wide admin into any organization's thread, a cross-tenant IDOR).
  defp authorize_assignment(actor, assignment_id) do
    with {:ok, assignment} <- Workouts.get_assignment(assignment_id) do
      participant? =
        Enum.any?(
          assignment.athlete_links,
          &(&1.athlete_id == actor.id and &1.athlete_status != :archived)
        )

      if participant? or organization_staff?(actor.id, assignment.organization_id) do
        {:ok, assignment}
      else
        {:error, :forbidden}
      end
    end
  end

  defp authorize_class_slot(%{id: actor_id}, %{organization_id: organization_id} = slot) do
    if organization_staff?(actor_id, organization_id) or
         Scheduling.get_approved_booking_for_class(actor_id, slot.id) do
      :ok
    else
      {:error, :forbidden}
    end
  end

  defp organization_staff?(actor_id, organization_id) do
    Enum.any?(Organizations.list_memberships(actor_id), fn %{membership: membership} ->
      membership.organization_id == organization_id and
        membership.role in [:owner, :admin, :coach] and membership.status == :active
    end)
  end

  defp add_org_staff_and_actor(participant_ids, actor_id, organization_id) do
    staff_ids =
      organization_id
      |> Organizations.list_staff_user_ids()
      |> Kernel.--([actor_id])

    Enum.uniq([actor_id | participant_ids ++ staff_ids])
  end
end
