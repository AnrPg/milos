defmodule MilosTraining.Application.GetOrCreateMessagingThread do
  @moduledoc """
  Authorizes a messaging context through its owning bounded context before
  asking Messaging to atomically create or return the thread.
  """

  alias MilosTraining.Application.TrackMessagingAnalytics
  alias MilosTraining.{Identity, Messaging, Organizations, Scheduling, Trials, Workouts}

  def call(%{id: actor_id}, %{context_type: :direct, participant_id: actor_id}),
    do: {:error, :self_conversation}

  def call(actor, %{context_type: :direct, participant_id: participant_id}) do
    with %{} <- Identity.find_by_id(participant_id) || {:error, :not_found} do
      Messaging.get_or_create_thread(%{
        context_type: :direct,
        actor_id: actor.id,
        participant_id: participant_id
      })
      |> TrackMessagingAnalytics.call()
    end
  end

  # Assignments and class slots are tenant data (ADR-133): they are only
  # reachable through a tenant context.
  def call(_actor, %{context_type: context_type})
      when context_type in [:assignment, :class_slot, :box],
      do: {:error, :organization_context_required}

  def call(_actor, _params), do: {:error, :bad_request}

  def call(%{organization_id: organization_id} = context, actor, %{
        context_type: :assignment,
        context_id: assignment_id
      })
      when is_binary(organization_id) do
    with {:ok, assignment} <- authorize_assignment(context, actor, assignment_id) do
      participant_ids =
        assignment.athlete_links
        |> Enum.reject(&(&1.athlete_status == :archived))
        |> Enum.map(& &1.athlete_id)
        |> add_org_staff_and_actor(actor.id, assignment.organization_id)

      context
      |> Messaging.with_tenant_context(fn ->
        Messaging.get_or_create_thread(%{
          context_type: :assignment,
          context_id: assignment_id,
          actor_id: actor.id,
          participants: participant_ids
        })
      end)
      |> TrackMessagingAnalytics.call()
    end
  end

  def call(%{organization_id: _} = context, actor, %{
        context_type: :class_slot,
        context_id: slot_id
      }) do
    with %{} = slot <- Scheduling.get_slot(context, slot_id) || {:error, :not_found},
         :ok <- authorize_class_slot(context, actor, slot) do
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
      |> TrackMessagingAnalytics.call()
    end
  end

  def call(%{organization_id: organization_id} = context, actor, %{
        context_type: :direct,
        participant_id: participant_id
      })
      when is_binary(organization_id) do
    with %{} <- Identity.find_by_id(participant_id) || {:error, :not_found},
         :ok <- ensure_direct_participants_share_tenant(context, actor.id, participant_id) do
      call(actor, %{context_type: :direct, participant_id: participant_id})
    end
  end

  # ADR-140 §6: the gym's thread with one member. Any staff member who may
  # message for the box opens it and joins it, so whoever picks it up next
  # continues the same conversation.
  def call(%{organization_id: organization_id} = context, actor, %{
        context_type: :box,
        context_id: member_id
      })
      when is_binary(organization_id) and is_binary(member_id) do
    with :ok <- Organizations.authorize_capability(context, :message_from_box),
         true <-
           (active_member?(member_id, organization_id) or trial_guest?(context, member_id)) ||
             {:error, :not_found},
         {:ok, thread} <-
           Messaging.with_tenant_context(context, fn ->
             Messaging.get_or_create_thread(%{
               context_type: :box,
               context_id: member_id,
               actor_id: actor.id,
               participants: [member_id, actor.id]
             })
           end),
         {:ok, _participant} <-
           Messaging.with_tenant_context(context, fn ->
             Messaging.add_participant(thread.id, actor.id)
           end) do
      Messaging.with_tenant_context(context, fn -> Messaging.get_thread(thread.id, actor.id) end)
      |> TrackMessagingAnalytics.call()
    end
  end

  def call(_context, actor, params), do: call(actor, params)

  # Assignments belong to one organization; an actor is authorized either as
  # a (non-archived) participant on it, or as owner/admin/coach staff of that
  # same organization - never by the account's global role (that let any
  # platform-wide admin into any organization's thread, a cross-tenant IDOR).
  defp authorize_assignment(context, actor, assignment_id) do
    with {:ok, assignment} <- Workouts.get_assignment(context, assignment_id) do
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

  defp authorize_class_slot(context, %{id: actor_id}, %{organization_id: organization_id} = slot) do
    if organization_staff?(actor_id, organization_id) or
         Scheduling.get_approved_booking_for_class(context, actor_id, slot.id) do
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

  defp ensure_direct_participants_share_tenant(
         %{organization_id: organization_id},
         actor_id,
         participant_id
       ) do
    with true <- active_member?(actor_id, organization_id),
         true <- active_member?(participant_id, organization_id) do
      :ok
    else
      _ -> {:error, :forbidden}
    end
  end

  # ADR-144: staff also write to people who tried a class (board 6 Q4).
  defp trial_guest?(context, user_id),
    do: Trials.list_requests(context, %{user_id: user_id, limit: 1}) != []

  defp active_member?(user_id, organization_id) do
    Enum.any?(Organizations.list_memberships(user_id), fn %{membership: membership} ->
      membership.organization_id == organization_id and membership.status == :active
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
