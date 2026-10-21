defmodule Palee.Application.IssuePlatformOrganizationInvitation do
  alias Palee.Organizations

  def call(platform_context, organization_id, params) do
    Organizations.issue_platform_invitation(platform_context, organization_id, params)
  end
end
