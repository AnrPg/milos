defmodule MilosTraining.Organizations.TenantContextTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Organizations.Domain.TenantAuthorization
  alias MilosTraining.Organizations.TenantContext

  @organization_id "b7c63d17-2039-4dd5-bf9d-e2f5845cde8d"
  @user_id "9d60a0ec-e742-4738-a12b-3eccf04ef60f"

  test "builds context only for an active membership in the requested active organization" do
    account = %{id: @user_id}
    organization = %{id: @organization_id, slug: "milos", status: :active}

    membership = %{
      id: Ecto.UUID.generate(),
      organization_id: @organization_id,
      user_id: @user_id,
      role: :admin,
      status: :active
    }

    assert {:ok, %TenantContext{} = context} =
             TenantAuthorization.build(account, organization, membership, %{transport: :http})

    assert context.organization_id == @organization_id
    assert context.user_id == @user_id
    assert :ok = TenantAuthorization.authorize(context, [:owner, :admin])
    assert {:error, :forbidden} = TenantAuthorization.authorize(context, [:member])
  end

  test "rejects stale and cross-organization memberships" do
    account = %{id: @user_id}
    organization = %{id: @organization_id, slug: "milos", status: :active}

    stale = %{
      id: Ecto.UUID.generate(),
      organization_id: @organization_id,
      user_id: @user_id,
      role: :member,
      status: :revoked
    }

    foreign = %{stale | organization_id: Ecto.UUID.generate(), status: :active}

    assert {:error, :inactive_membership} =
             TenantAuthorization.build(account, organization, stale, %{})

    assert {:error, :membership_mismatch} =
             TenantAuthorization.build(account, organization, foreign, %{})
  end
end
