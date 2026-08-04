defmodule MilosTraining.Organizations.Queries.ListMemberships do
  alias MilosTraining.Organizations.OrganizationStore

  def call(user_id), do: OrganizationStore.list_memberships(user_id)
end
