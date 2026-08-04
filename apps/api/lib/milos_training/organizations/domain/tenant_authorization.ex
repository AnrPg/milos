defmodule MilosTraining.Organizations.Domain.TenantAuthorization do
  @moduledoc false

  alias MilosTraining.Organizations.Domain.MembershipPolicy
  alias MilosTraining.Organizations.TenantContext

  def build(account, organization, membership, request_metadata)
      when is_map(account) and is_map(organization) and is_map(membership) do
    cond do
      organization.status != :active ->
        {:error, :inactive_organization}

      membership.organization_id != organization.id or membership.user_id != account.id ->
        {:error, :membership_mismatch}

      not MembershipPolicy.authorized_status?(membership.status) ->
        {:error, :inactive_membership}

      true ->
        {:ok,
         %TenantContext{
           organization: organization,
           membership: membership,
           account: account,
           organization_id: organization.id,
           membership_id: membership.id,
           user_id: account.id,
           role: membership.role,
           request_metadata: request_metadata || %{}
         }}
    end
  end

  def build(_account, _organization, _membership, _request_metadata),
    do: {:error, :membership_required}

  def authorize(%TenantContext{role: role}, roles) when is_list(roles) do
    if role in roles, do: :ok, else: {:error, :forbidden}
  end
end
