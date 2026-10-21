defmodule Palee.Application.ListProvisionedOrganizations do
  alias Palee.Organizations

  def call(platform_context), do: Organizations.list_provisioned_organizations(platform_context)
end
