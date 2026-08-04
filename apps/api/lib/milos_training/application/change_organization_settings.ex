defmodule MilosTraining.Application.ChangeOrganizationSettings do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.update_organization_settings(platform_context, organization_id, params)
end
