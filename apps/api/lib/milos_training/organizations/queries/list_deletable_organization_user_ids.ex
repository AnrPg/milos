defmodule MilosTraining.Organizations.Queries.ListDeletableOrganizationUserIds do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context, organization_id) when is_binary(organization_id) do
    {:ok,
     RepoContext.run(%{user_id: context.user_id}, fn ->
       OrganizationStore.list_deletable_organization_user_ids(organization_id, context.user_id)
     end)}
  end

  def call(%PlatformContext{}, _organization_id), do: {:error, :not_found}
  def call(_context, _organization_id), do: {:error, :vendor_required}
end
