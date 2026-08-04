defmodule MilosTraining.Application.ListProvisionedOrganizations do
  alias MilosTraining.Organizations

  def call(platform_context), do: Organizations.list_provisioned_organizations(platform_context)
end
