defmodule MilosTraining.Application.RenameOrganization do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, name),
    do: Organizations.rename_organization(platform_context, organization_id, name)
end
