defmodule Palee.Organizations.Commands.AddMembership do
  alias Palee.Organizations.OrganizationStore

  def call(params), do: OrganizationStore.add_membership(params)
end
