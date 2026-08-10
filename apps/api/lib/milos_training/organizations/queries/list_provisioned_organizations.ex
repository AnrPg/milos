defmodule MilosTraining.Organizations.Queries.ListProvisionedOrganizations do
  alias MilosTraining.Infrastructure.Tenancy.RepoContext
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{} = context) do
    {:ok,
     RepoContext.run(%{user_id: context.user_id}, fn -> OrganizationStore.list_organizations() end)}
  end

  def call(_context), do: {:error, :vendor_required}
end
