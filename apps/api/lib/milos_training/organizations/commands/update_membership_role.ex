defmodule MilosTraining.Organizations.Commands.UpdateMembershipRole do
  alias MilosTraining.Organizations.Domain.MembershipPolicy
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{}, organization_id, membership_id, params)
      when is_binary(organization_id) and is_binary(membership_id) do
    role = normalize_role(value(params, :role))

    if role in MembershipPolicy.roles() do
      OrganizationStore.update_membership_role(organization_id, membership_id, role)
    else
      {:error, [role: "is invalid"]}
    end
  end

  def call(%PlatformContext{}, _organization_id, _membership_id, _params),
    do: {:error, :not_found}

  def call(_context, _organization_id, _membership_id, _params),
    do: {:error, :vendor_required}

  defp normalize_role(role) when is_atom(role), do: role

  defp normalize_role(role) when is_binary(role) do
    Enum.find(MembershipPolicy.roles(), role, &(Atom.to_string(&1) == role))
  end

  defp normalize_role(role), do: role
  defp value(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
