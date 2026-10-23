defmodule Palee.Application.ListOrganizationMemberships do
  alias Palee.Organizations

  # ADR-185: a person's own organiser organisation is not one of their gyms.
  def call(%{id: user_id}),
    do: {:ok, user_id |> Organizations.list_memberships() |> Organizations.provider_memberships()}
end
