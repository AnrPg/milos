defmodule MilosTraining.Application.ProvisionOrganization do
  alias MilosTraining.Organizations

  def call(platform_context, params),
    do: Organizations.provision_organization(platform_context, params)
end
