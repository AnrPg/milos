defmodule MilosTraining.Application.DeleteOrganization do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id),
    do: Organizations.delete_organization(platform_context, organization_id)
end
