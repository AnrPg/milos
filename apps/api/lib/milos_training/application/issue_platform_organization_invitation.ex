defmodule MilosTraining.Application.IssuePlatformOrganizationInvitation do
  alias MilosTraining.Organizations

  def call(platform_context, organization_id, params) do
    Organizations.issue_platform_invitation(platform_context, organization_id, params)
  end
end
