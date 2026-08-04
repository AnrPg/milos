defmodule MilosTraining.Organizations.Queries.ListProvisionedOrganizations do
  alias MilosTraining.Organizations.{OrganizationStore, PlatformContext}

  def call(%PlatformContext{}), do: {:ok, OrganizationStore.list_organizations()}
  def call(_context), do: {:error, :platform_owner_required}
end
