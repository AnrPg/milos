defmodule MilosTraining.Application.ListOrganizationMemberships do
  alias MilosTraining.Organizations

  def call(%{id: user_id}), do: {:ok, Organizations.list_memberships(user_id)}
end
