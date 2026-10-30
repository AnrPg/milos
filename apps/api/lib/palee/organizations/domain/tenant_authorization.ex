defmodule Palee.Organizations.Domain.TenantAuthorization do
  @moduledoc false

  alias Palee.Organizations.Domain.{AccessPolicy, LocationScopePolicy, MembershipPolicy}
  alias Palee.Organizations.TenantContext

  @doc """
  The tenant context of an account in a gym. `location_ids` are the active
  branches of a branch-scoped membership (ADR-186); they are ignored when the
  membership works everywhere.
  """
  def build(
        account,
        organization,
        membership,
        request_metadata,
        role_grants \\ %{},
        location_ids \\ []
      )

  def build(account, organization, membership, request_metadata, role_grants, location_ids)
      when is_map(account) and is_map(organization) and is_map(membership) do
    cond do
      organization.status != :active ->
        {:error, :inactive_organization}

      membership.organization_id != organization.id or membership.user_id != account.id ->
        {:error, :membership_mismatch}

      not MembershipPolicy.authorized_status?(membership.status) ->
        {:error, :inactive_membership}

      true ->
        roles = membership_roles(membership)
        coach_scope = Map.get(membership, :coach_scope) || :own

        # ADR-185: organiser organisations have no branches, so their people
        # work everywhere whatever a stored scope says.
        location_scope =
          if Map.get(organization, :provider_kind) == "organiser",
            do: :all,
            else:
              LocationScopePolicy.effective(
                roles,
                Map.get(membership, :all_locations, true),
                location_ids
              )

        {:ok,
         %TenantContext{
           organization: organization,
           membership: membership,
           account: account,
           organization_id: organization.id,
           membership_id: membership.id,
           user_id: account.id,
           role: MembershipPolicy.primary_role(roles) || membership.role,
           roles: roles,
           capabilities:
             roles
             |> AccessPolicy.capabilities(
               coach_scope: coach_scope,
               role_grants: role_grants || %{}
             )
             |> LocationScopePolicy.narrow_capabilities(location_scope),
           coach_scope: coach_scope,
           location_scope: location_scope,
           request_metadata: request_metadata || %{}
         }}
    end
  end

  def build(_account, _organization, _membership, _request_metadata, _role_grants, _ids),
    do: {:error, :membership_required}

  @doc """
  ADR-129 seam: is the acting member a coach of this tenant?

  Mirrors the SQL helper `palee_acting_user_coaches(org_id)` used by the PR
  visibility RLS policies; the two must change together. With role sets
  (ADR-099) a coach is any membership whose roles include `:coach`, so an owner
  or admin who also coaches qualifies; coach scope and coaching relationships
  must not narrow it.
  """
  def coaches?(%TenantContext{} = context), do: :coach in roles(context)
  def coaches?(_context), do: false

  def authorize(%TenantContext{} = context, roles) when is_list(roles) do
    if any_role?(context, roles), do: :ok, else: {:error, :forbidden}
  end

  defp membership_roles(%{roles: [_ | _] = roles}), do: roles
  defp membership_roles(%{role: role}) when not is_nil(role), do: [role]
  defp membership_roles(_membership), do: []

  @doc "Roles the account holds in the context's gym (ADR-099)."
  def roles(%{roles: [_ | _] = roles}), do: roles
  def roles(%{role: role}) when not is_nil(role), do: [role]
  def roles(_context), do: []

  @doc """
  Whether the account works at the gym: any staff role (owner and admin
  included), never a client or guest role (ADR-272).
  """
  def staff?(context), do: context |> roles() |> MembershipPolicy.staff?()

  def any_role?(context, roles) when is_list(roles),
    do: context |> roles() |> Enum.any?(&(&1 in roles))

  @doc """
  The account's capabilities in the context's gym (ADR-099). A context built
  without them (tests, jobs) derives them from its roles.
  """
  def capabilities(%{capabilities: capabilities})
      when is_map(capabilities) and map_size(capabilities) > 0,
      do: capabilities

  def capabilities(context),
    do: AccessPolicy.capabilities(roles(context), coach_scope: Map.get(context, :coach_scope))

  def can?(context, capability), do: AccessPolicy.can?(capabilities(context), capability)

  @doc "`:all`, `:own`, `:status` or nil when the capability is missing."
  def scope(context, capability), do: AccessPolicy.scope(capabilities(context), capability)

  def authorize_capability(context, capability) do
    if can?(context, capability), do: :ok, else: {:error, :forbidden}
  end
end
