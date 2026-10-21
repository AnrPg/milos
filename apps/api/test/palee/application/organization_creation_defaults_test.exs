defmodule Palee.Application.OrganizationCreationDefaultsTest do
  @moduledoc """
  ADR-133 / TD-094: both ways a gym comes into existence give it the platform
  defaults (ADR-128 scale levels) in the same transaction as the gym itself.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{CreateOwnedOrganization, ProvisionOrganization}
  alias Palee.{Organizations, Workouts}

  @default_levels [{"scaled", "Scaled", 1}, {"rx", "Rx", 2}, {"rx-plus", "Rx+", 3}]

  test "vendor provisioning seeds the default scale levels" do
    vendor = user_fixture()
    {:ok, _vendor} = bypass_rls(fn -> Organizations.grant_vendor(vendor.id) end)
    {:ok, platform} = Organizations.resolve_platform_context(vendor)

    assert {:ok, %{organization: organization, initial_owner_token: token}} =
             ProvisionOrganization.call(platform, %{
               "name" => "Provisioned Gym",
               "slug" => "provisioned-gym",
               "initial_owner_email" => "owner@provisioned.test"
             })

    assert is_binary(token)
    assert levels(organization.id, vendor.id) == @default_levels
  end

  test "an owner's new gym gets the default scale levels and the owner membership" do
    owner = user_fixture()

    bypass_rls(fn ->
      {:ok, home} = Organizations.create_organization(%{name: "Owner Home Gym"})

      {:ok, _} =
        Organizations.add_membership(%{
          organization_id: home.id,
          user_id: owner.id,
          role: :owner,
          roles: [:owner],
          status: :active,
          joined_at: DateTime.utc_now()
        })
    end)

    assert {:ok, organization} = CreateOwnedOrganization.call(owner, %{name: "Owner Second Gym"})

    assert :owner in Organizations.member_roles(organization.id, owner.id)
    assert levels(organization.id, owner.id) == @default_levels
  end

  test "a non-owner cannot create a gym" do
    assert {:error, :owner_required} =
             CreateOwnedOrganization.call(user_fixture(), %{name: "Nope Gym"})
  end

  defp levels(organization_id, user_id) do
    %{organization_id: organization_id, user_id: user_id}
    |> Workouts.list_scale_levels()
    |> Enum.map(&{&1.slug, &1.label, &1.sort_order})
  end
end
