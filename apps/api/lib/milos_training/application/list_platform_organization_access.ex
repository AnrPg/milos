defmodule MilosTraining.Application.ListPlatformOrganizationAccess do
  alias MilosTraining.{Identity, Organizations}

  def call(platform_context, organization_id) do
    with {:ok, %{organization: organization, memberships: memberships}} <-
           Organizations.list_organization_memberships(platform_context, organization_id) do
      users_by_id =
        memberships
        |> Enum.map(& &1.user_id)
        |> Identity.list_by_ids()
        |> Map.new(&{&1.id, &1})

      {:ok,
       %{
         organization: organization,
         memberships: Enum.map(memberships, &decorate(&1, users_by_id))
       }}
    end
  end

  defp decorate(membership, users_by_id) do
    %{membership: membership, user: Map.get(users_by_id, membership.user_id)}
  end
end
