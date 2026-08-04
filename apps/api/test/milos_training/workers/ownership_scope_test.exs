defmodule MilosTraining.Workers.OwnershipScopeTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Application.OwnershipKeys

  test "tenant jobs reject a missing organization scope" do
    assert {:error, :missing_organization_scope} =
             OwnershipKeys.require_tenant_args(%{"booking_id" => Ecto.UUID.generate()})
  end

  test "personal jobs reject a missing owner scope" do
    assert {:error, :missing_user_scope} =
             OwnershipKeys.require_user_args(%{"operation" => "delete"})
  end

  test "canonical keys cannot escape their ownership prefix" do
    context = %{organization_id: "tenant-id", user_id: "user-id"}

    assert OwnershipKeys.tenant(context, "schedule") == "org:tenant-id:schedule"
    assert OwnershipKeys.user(context, "landing") == "user:user-id:landing"

    assert OwnershipKeys.tenant_object(context, "/invoices/../invoice.pdf") ==
             "organizations/tenant-id/invoices/invoice.pdf"

    assert OwnershipKeys.user_object(context, "exports/result.csv") ==
             "users/user-id/exports/result.csv"
  end
end
