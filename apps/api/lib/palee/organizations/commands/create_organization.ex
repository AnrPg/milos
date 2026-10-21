defmodule Palee.Organizations.Commands.CreateOrganization do
  alias Palee.Organizations.OrganizationStore

  def call(params), do: OrganizationStore.create_organization(params)
end
