defmodule MilosTraining.Organizations.Queries.ListOrganizationMemberships do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, organization_id) when is_binary(organization_id) do
    RepoContext.run(%{user_id: context.user_id}, fn ->
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
    end)
  end

  def call(_context, _organization_id), do: {:error, :vendor_required}
end
