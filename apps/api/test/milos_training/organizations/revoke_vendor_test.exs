defmodule MilosTraining.Organizations.RevokeVendorTest do
  @moduledoc """
  F-12: proves platform (vendor) access can be withdrawn without hand-editing
  the `vendors` table.
  """
  use MilosTraining.DataCase, async: false

  alias MilosTraining.Organizations
  alias MilosTraining.Organizations.OrganizationStore
  alias MilosTraining.TestFixtures

  test "revoking clears the account's active vendor status" do
    user = TestFixtures.admin_fixture()

    assert {:ok, _vendor} = Organizations.grant_vendor(user.id)
    assert %{status: :active} = OrganizationStore.get_vendor(user.id)

    assert {:ok, vendor} = Organizations.revoke_vendor(user.id)
    assert vendor.status == :revoked

    # get_vendor/1 only matches active rows, so platform context resolution
    # stops seeing this account immediately.
    refute OrganizationStore.get_vendor(user.id)
    assert {:error, _reason} = Organizations.resolve_platform_context(user)
  end

  test "revoking preserves the row so the grant stays auditable" do
    user = TestFixtures.admin_fixture()
    {:ok, _vendor} = Organizations.grant_vendor(user.id)
    {:ok, revoked} = Organizations.revoke_vendor(user.id)

    assert revoked.user_id == user.id
    assert revoked.status == :revoked
  end

  test "a revoked vendor can be granted again" do
    user = TestFixtures.admin_fixture()
    {:ok, _} = Organizations.grant_vendor(user.id)
    {:ok, _} = Organizations.revoke_vendor(user.id)

    assert {:ok, _vendor} = Organizations.grant_vendor(user.id)
    assert %{status: :active} = OrganizationStore.get_vendor(user.id)
  end

  test "revoking an account that was never a vendor reports not_found" do
    user = TestFixtures.admin_fixture()

    assert {:error, :not_found} = Organizations.revoke_vendor(user.id)
  end
end
