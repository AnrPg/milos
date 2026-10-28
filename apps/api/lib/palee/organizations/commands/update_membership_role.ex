defmodule Palee.Organizations.Commands.UpdateMembershipRole do
  @moduledoc """
  The vendor sets a membership's roles from the platform console. The vendor
  sits above every gym role (ADR-219), so it may set any role set, down to
  owner; a gym still always keeps an active owner. `roles` (a set) wins over
  the single `role` older clients send, which replaces the set.
  """

  alias Palee.Infrastructure.Tenancy.RepoContext
  alias Palee.Organizations.Domain.MembershipPolicy
  alias Palee.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, organization_id, membership_id, params)
      when is_binary(organization_id) and is_binary(membership_id) do
    case requested_roles(params) do
      {:ok, roles} ->
        RepoContext.run(%{user_id: context.user_id}, fn ->
          change_roles(organization_id, membership_id, roles)
        end)

      {:error, _reason} ->
        {:error, [role: "is invalid"]}
    end
  end

  def call(%PlatformContext{}, _organization_id, _membership_id, _params),
    do: {:error, :not_found}

  def call(_context, _organization_id, _membership_id, _params),
    do: {:error, :vendor_required}

  defp change_roles(organization_id, membership_id, roles) do
    with %{} = membership <-
           OrganizationStore.get_membership_by_id(organization_id, membership_id) ||
             {:error, :not_found},
         :ok <- keep_an_owner(organization_id, membership, roles) do
      OrganizationStore.update_membership_roles(organization_id, membership.id, roles)
    end
  end

  defp requested_roles(params) do
    case value(params, :roles) do
      [_ | _] = roles -> MembershipPolicy.normalize_roles(roles)
      _other -> MembershipPolicy.normalize_roles(List.wrap(value(params, :role)))
    end
  end

  defp keep_an_owner(organization_id, membership, roles) do
    losing_owner? = :owner in (membership.roles || []) and :owner not in roles

    other_owner? =
      organization_id
      |> OrganizationStore.list_organization_memberships()
      |> Enum.any?(
        &(&1.id != membership.id and &1.status == :active and :owner in (&1.roles || [&1.role]))
      )

    if losing_owner? and not other_owner?, do: {:error, :last_owner}, else: :ok
  end

  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
