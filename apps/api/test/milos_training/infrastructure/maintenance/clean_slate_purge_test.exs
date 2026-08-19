defmodule MilosTraining.Infrastructure.Maintenance.CleanSlatePurgeTest do
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Infrastructure.Maintenance.CleanSlatePurge
  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.{Organization, OrganizationMembership, Vendor}
  alias MilosTraining.Repo

  import Ecto.Query
  import MilosTraining.TestFixtures

  @confirmation "PURGE_ALL_TENANT_DATA_KEEP_SAAS_OWNER"

  setup do
    previous_confirmation = System.get_env("MILOS_CONFIRM_PROD_PURGE")
    previous_owner = System.get_env("MILOS_SAAS_OWNER_NICKNAME")

    on_exit(fn ->
      restore_env("MILOS_CONFIRM_PROD_PURGE", previous_confirmation)
      restore_env("MILOS_SAAS_OWNER_NICKNAME", previous_owner)
    end)
  end

  test "refuses to run without explicit confirmation" do
    System.delete_env("MILOS_CONFIRM_PROD_PURGE")

    assert {:error, {:missing_confirmation, _message}} = CleanSlatePurge.run_from_env()
  end

  test "purges tenant data and non-owner accounts while keeping the active SaaS owner" do
    owner = user_fixture(%{nickname: "saas_owner"})
    client = user_fixture(%{nickname: "tenant_client", email: "tenant@example.test"})
    extra_vendor = user_fixture(%{nickname: "extra_vendor"})

    {:ok, _owner_vendor} = Organizations.grant_vendor(owner.id)
    {:ok, _extra_vendor} = Organizations.grant_vendor(extra_vendor.id)
    {:ok, organization} = Organizations.create_organization(%{name: "Temporary Tenant"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: client.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    System.put_env("MILOS_CONFIRM_PROD_PURGE", @confirmation)
    System.put_env("MILOS_SAAS_OWNER_NICKNAME", "SAAS_OWNER")

    assert {:ok, summary} = CleanSlatePurge.purge_postgres_except_saas_owner("SAAS_OWNER")

    assert summary.preserved_owner_id == owner.id
    assert Repo.get(Organization, organization.id) == nil

    refute Repo.exists?(
             from membership in OrganizationMembership,
               where: membership.organization_id == ^organization.id
           )

    assert Repo.exists?(from user in MilosTraining.Identity.User, where: user.id == ^owner.id)
    refute Repo.exists?(from user in MilosTraining.Identity.User, where: user.id == ^client.id)

    refute Repo.exists?(
             from user in MilosTraining.Identity.User, where: user.id == ^extra_vendor.id
           )

    assert Repo.exists?(
             from vendor in Vendor,
               where: vendor.user_id == ^owner.id and vendor.status == :active
           )

    refute Repo.exists?(from vendor in Vendor, where: vendor.user_id == ^extra_vendor.id)
  end

  test "repairs a missing SaaS owner vendor grant while purging stale data" do
    owner = user_fixture(%{nickname: "prod_owner_regas"})
    stale_client = user_fixture(%{nickname: "stale_client", email: "stale@example.test"})
    {:ok, _organization} = Organizations.create_organization(%{name: "Stale Tenant"})

    refute Repo.exists?(from vendor in Vendor, where: vendor.user_id == ^owner.id)

    assert {:ok, summary} = CleanSlatePurge.purge_postgres_except_saas_owner("PROD_OWNER_REGAS")

    assert summary.preserved_owner_id == owner.id
    assert summary.preserved_owner_vendor_id
    assert Repo.exists?(from user in MilosTraining.Identity.User, where: user.id == ^owner.id)

    refute Repo.exists?(
             from user in MilosTraining.Identity.User, where: user.id == ^stale_client.id
           )

    assert Repo.exists?(
             from vendor in Vendor,
               where: vendor.user_id == ^owner.id and vendor.status == :active
           )
  end

  defp restore_env(name, nil), do: System.delete_env(name)
  defp restore_env(name, value), do: System.put_env(name, value)
end
