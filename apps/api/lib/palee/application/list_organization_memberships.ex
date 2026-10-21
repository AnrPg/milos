defmodule Palee.Application.ListOrganizationMemberships do
  alias Palee.Organizations

  def call(%{id: user_id}), do: {:ok, Organizations.list_memberships(user_id)}
end
