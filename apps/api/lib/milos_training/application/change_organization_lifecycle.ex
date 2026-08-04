defmodule MilosTraining.Application.ChangeOrganizationLifecycle do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, status),
    do: Organizations.update_organization_lifecycle(platform_context, organization_id, status)
end
