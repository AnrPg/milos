defmodule MilosTraining.Organizations.Commands.CreateOrganization do
  alias MilosTraining.Organizations.OrganizationStore

  def call(params), do: OrganizationStore.create_organization(params)
end
