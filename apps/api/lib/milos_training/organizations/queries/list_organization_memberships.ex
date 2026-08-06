defmodule MilosTraining.Organizations.Queries.ListOrganizationMemberships do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{}, organization_id) when is_binary(organization_id) do
    case OrganizationStore.get_organization_by_id(organization_id) do
      nil ->
        {:error, :not_found}

      organization ->
        {:ok,
         %{
           organization: organization,
           memberships: OrganizationStore.list_organization_memberships(organization_id)
         }}
    end
  end

  def call(_context, _organization_id), do: {:error, :vendor_required}
end
