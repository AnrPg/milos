defmodule MilosTraining.Organizations.Commands.AddMembership do
  alias MilosTraining.Organizations.OrganizationStore

  def call(params), do: OrganizationStore.add_membership(params)
end
