defmodule Palee.Application.ChangeOrganizationSettings do
  alias Palee.Organizations

  def call(platform_context, organization_id, params),
    do: Organizations.update_organization_settings(platform_context, organization_id, params)
end
