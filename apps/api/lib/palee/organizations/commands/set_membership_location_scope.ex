defmodule Palee.Organizations.Commands.SetMembershipLocationScope do
  @moduledoc """
  Sets the branches a person works at as staff (ADR-186): «Όλα τα
  καταστήματα» or a list of the gym's locations.

  Whoever may grant staff roles decides it, inside their own scope: a branch
  manager scopes people only to their own branches, and cannot touch staff
  who also work elsewhere. Owners always work everywhere, and nobody changes
  their own scope.
  """

  alias Palee.Application.BroadcastUserSync
  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.{LocationScopePolicy, MembershipPolicy, TenantAuthorization}
  alias Palee.Organizations.{LocationScopeStore, OrganizationStore}

  @doc """
  `scope` is `:all` or a list of location ids already checked against the
  gym's active locations (`LocationScopePolicy.parse/2`).
  """
  def call(context, user_id, scope) when is_binary(user_id) do
    with :ok <- TenantAuthorization.authorize_capability(context, :grant_staff_roles),
         :ok <- valid_scope(scope) do
      RepoContext.run(context, fn -> change_scope(context, user_id, scope) end)
    end
  end

  def call(_context, _user_id, _scope), do: {:error, :not_found}

  defp change_scope(context, user_id, scope) do
    with %{} = membership <-
           OrganizationStore.get_membership(context.organization_id, user_id) ||
             {:error, :not_found},
         :ok <- refuse_self_change(context, membership),
         :ok <- owners_work_everywhere(membership, scope),
         :ok <- role_ceiling(context, membership),
         :ok <- authorize_manage(context, membership, membership.roles),
         :ok <- LocationScopePolicy.authorize_grant(LocationScopePolicy.scope(context), scope),
         {:ok, updated} <- LocationScopeStore.put_scope(context, membership.id, scope) do
      BroadcastUserSync.for_user(updated.user_id, ["session"],
        reason: "location_scope_changed",
        payload: %{organization_id: context.organization_id}
      )

      {:ok, %{membership: updated, location_scope: scope}}
    end
  end

  @doc """
  The scope stored on a membership, whatever its roles: `:all` or the ids of
  its active branches.
  """
  def stored_scope(context, %{all_locations: false} = membership),
    do: LocationScopeStore.location_ids(context, membership.id)

  def stored_scope(_context, _membership), do: :all

  @doc """
  `:ok` when the acting granter may manage someone who holds (or is about to
  hold) `roles`: staff must work inside the granter's branches.
  """
  def authorize_manage(context, membership, roles) do
    granter_scope = LocationScopePolicy.scope(context)

    cond do
      granter_scope == :all ->
        :ok

      LocationScopePolicy.can_manage?(
        granter_scope,
        membership.roles,
        stored(context, membership)
      ) and
          LocationScopePolicy.can_manage?(granter_scope, roles, stored(context, membership)) ->
        :ok

      true ->
        {:error, :location_scope_exceeded}
    end
  end

  defp stored(context, membership), do: stored_scope(context, membership)

  defp valid_scope(:all), do: :ok
  defp valid_scope([_ | _] = ids), do: if(Enum.all?(ids, &is_binary/1), do: :ok, else: invalid())
  defp valid_scope(_scope), do: invalid()

  defp invalid, do: {:error, :invalid_location_scope}

  defp refuse_self_change(context, membership) do
    if membership.user_id == context.user_id,
      do: {:error, :cannot_change_own_membership},
      else: :ok
  end

  # Changing where someone works is part of their roles: an admin scopes
  # staff below admin, only an owner scopes an admin (ADR-099 ceiling).
  defp role_ceiling(context, membership) do
    granter_roles = TenantAuthorization.roles(context)

    if Enum.all?(membership.roles || [], &MembershipPolicy.can_grant_role?(granter_roles, &1)),
      do: :ok,
      else: {:error, :role_ceiling_exceeded}
  end

  defp owners_work_everywhere(membership, scope) do
    if :owner in (membership.roles || []) and scope != :all,
      do: {:error, :owner_location_scope},
      else: :ok
  end
end
