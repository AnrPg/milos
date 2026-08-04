defmodule MilosTraining.Application.UpdatePlatformOrganizationMembershipRole do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, membership_id, params) do
    Organizations.update_membership_role(platform_context, organization_id, membership_id, params)
  end
end
