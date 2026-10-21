defmodule Palee.Application.ManageCoachingRelationships do
  @moduledoc """
  Starts and ends coaching relationships (ADR-100). Owners and admins assign
  any coach to any client; a coach may take an athlete as their own client,
  which notifies the gym's owners and admins; a coach's invitation makes the
  redeemed client theirs. Ending one takes the client out of that coach's
  PT squads (ADR-168).
  """

  alias Palee.Application.PtSquads
  alias Palee.{Coaching, Identity, Notifications, Organizations}
  alias Palee.Coaching.Domain.CoachingRelationshipPolicy

  def assign(context, coach_user_id, client_user_id) do
    with :ok <- Organizations.authorize_capability(context, :assign_coaches) do
      start(context, :assigned, coach_user_id, client_user_id)
    end
  end

  def self_assign(context, client_user_id) do
    with :ok <- Organizations.authorize_capability(context, :self_assign_athletes),
         {:ok, relationship} <- start(context, :self_assigned, context.user_id, client_user_id) do
      notify_managers(context, client_user_id)
      {:ok, relationship}
    end
  end

  @doc "Called after an invitation is redeemed; a no-op unless a coach invited."
  def start_invited(_organization_id, %{coach_user_id: nil}, _client_user_id), do: :ok

  def start_invited(organization_id, %{coach_user_id: coach_user_id}, client_user_id)
      when is_binary(coach_user_id) do
    context = %{organization_id: organization_id, user_id: coach_user_id}

    case start(context, :invited, coach_user_id, client_user_id) do
      {:ok, _relationship} -> :ok
      _not_started -> :ok
    end
  end

  def start_invited(_organization_id, _invitation, _client_user_id), do: :ok

  def finish(context, relationship_id) do
    relationship =
      context
      |> Coaching.list_relationships(%{})
      |> Enum.find(&(&1.id == relationship_id))

    cond do
      is_nil(relationship) ->
        {:error, :not_found}

      Organizations.can?(context, :assign_coaches) or
          relationship.coach_user_id == context.user_id ->
        with {:ok, ended} <- Coaching.end_relationship(context, relationship_id, context.user_id) do
          # ADR-168: squad membership follows coaching.
          :ok =
            PtSquads.coaching_ended(
              context,
              relationship.coach_user_id,
              relationship.client_user_id
            )

          {:ok, ended}
        end

      true ->
        {:error, :forbidden}
    end
  end

  @doc """
  Relationships with both people's nicknames: a coach with scope `:own` sees
  their own; owners, admins and head coaches see all, or one coach's.
  """
  def list(context, filters \\ %{}) do
    filters =
      if Organizations.capability_scope(context, :manage_coaching) == :all,
        do: filters,
        else: Map.put(filters, :coach_user_id, context.user_id)

    relationships = Coaching.list_relationships(context, filters)

    nicknames =
      relationships
      |> Enum.flat_map(&[&1.coach_user_id, &1.client_user_id])
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, &1.nickname})

    Enum.map(relationships, fn relationship ->
      Map.merge(relationship, %{
        coach_nickname: Map.get(nicknames, relationship.coach_user_id),
        client_nickname: Map.get(nicknames, relationship.client_user_id)
      })
    end)
  end

  defp start(context, origin, coach_user_id, client_user_id) do
    coach_roles = Organizations.member_roles(context.organization_id, coach_user_id)
    client_roles = Organizations.member_roles(context.organization_id, client_user_id)

    with :ok <- CoachingRelationshipPolicy.can_start?(origin, coach_roles, client_roles) do
      Coaching.start_relationship(context, %{
        coach_user_id: coach_user_id,
        client_user_id: client_user_id,
        origin: CoachingRelationshipPolicy.origin(origin),
        started_by_id: context.user_id
      })
    end
  end

  defp notify_managers(context, client_user_id) do
    people = Identity.list_by_ids([context.user_id, client_user_id]) |> Map.new(&{&1.id, &1})

    context.organization_id
    |> Organizations.list_manager_user_ids()
    |> Enum.reject(&(&1 == context.user_id))
    |> Enum.each(fn manager_id ->
      Notifications.process_event("coach_client_assigned", %{
        user_id: manager_id,
        organization_id: context.organization_id,
        coach_nickname: people[context.user_id] && people[context.user_id].nickname,
        client_nickname: people[client_user_id] && people[client_user_id].nickname,
        client_user_id: client_user_id
      })
    end)
  end
end
