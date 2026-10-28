defmodule PaleeWeb.StaffFinanceProfilesTest do
  @moduledoc """
  ADR-217: staff are shown by their roles in the box and never have a
  finance profile, a package or a place in the finance ledger; someone who is
  staff and also holds a client role is treated as that client.
  """
  use PaleeWeb.ConnCase, async: true

  import Palee.TestFixtures

  alias Palee.{Finance, Organizations, Repo}

  setup do
    owner = admin_fixture(%{nickname: "adr217_owner"})
    coach = user_fixture(%{role: :member, nickname: "adr217_coach"})
    coach_member = user_fixture(%{role: :member, nickname: "adr217_coach_member"})
    member = user_fixture(%{role: :member, nickname: "adr217_member"})

    {:ok, organization} =
      Organizations.create_organization(%{
        name: "ADR-217 Box #{System.unique_integer([:positive])}"
      })

    join(organization, owner, [:owner])
    join(organization, coach, [:coach])
    join(organization, coach_member, [:coach, :member])
    join(organization, member, [:member])

    {:ok, context} = Organizations.resolve_tenant_context(owner, organization.slug)

    {:ok, package} =
      Finance.create_package(context, %{
        code: "adr217_monthly",
        name: "ADR-217 Monthly",
        family: "unlimited",
        billing_period: "monthly",
        base_price_cents: 6000
      })

    %{
      owner: owner,
      coach: coach,
      coach_member: coach_member,
      member: member,
      organization: organization,
      context: context,
      package: package
    }
  end

  test "the finance ledger lists clients only, never staff-only people", %{
    conn: conn,
    owner: owner,
    coach: coach,
    coach_member: coach_member,
    member: member,
    organization: organization
  } do
    rows =
      conn
      |> put_bearer_token(owner)
      |> get("/api/org/#{organization.slug}/admin/finance/members")
      |> json_response(200)
      |> Map.fetch!("members")

    ids = Enum.map(rows, & &1["id"])
    assert member.id in ids
    assert coach_member.id in ids
    refute owner.id in ids
    refute coach.id in ids
    assert Enum.find(rows, &(&1["id"] == coach_member.id))["identity_role"] == "member"
  end

  test "staff-only people cannot get a finance profile or a package", %{
    conn: conn,
    owner: owner,
    coach: coach,
    organization: organization,
    context: context,
    package: package
  } do
    for target <- [owner, coach] do
      assert %{"code" => "not_a_client"} =
               build_conn()
               |> put_bearer_token(owner)
               |> patch("/api/org/#{organization.slug}/admin/finance/members/#{target.id}", %{
                 status: "active"
               })
               |> json_response(422)

      assert %{"code" => "not_a_client"} =
               build_conn()
               |> put_bearer_token(owner)
               |> post(
                 "/api/org/#{organization.slug}/admin/finance/members/#{target.id}/packages",
                 %{membership_package_id: package.id}
               )
               |> json_response(422)

      assert Finance.get_member_profile(context, target.id) == nil
    end

    _ = conn
  end

  test "staff given a client role explicitly get a package like any client", %{
    conn: conn,
    owner: owner,
    coach_member: coach_member,
    organization: organization,
    context: context,
    package: package
  } do
    conn
    |> put_bearer_token(owner)
    |> post(
      "/api/org/#{organization.slug}/admin/finance/members/#{coach_member.id}/packages",
      %{membership_package_id: package.id}
    )
    |> json_response(201)

    profile = Finance.get_member_profile(context, coach_member.id)
    assert profile.membership.user_type_snapshot == "member"
    assert profile.membership.status == "active"
  end

  test "an owner's profile reads Owner and offers no finance", %{
    conn: conn,
    owner: owner,
    coach_member: coach_member,
    organization: organization
  } do
    profile =
      conn
      |> put_bearer_token(owner)
      |> get("/api/org/#{organization.slug}/admin/users/#{owner.id}")
      |> json_response(200)
      |> get_in(["user"])

    assert profile["identity"]["role"] == "owner"
    refute "finance" in profile["available_sections"]
    refute Map.has_key?(profile["operational_links"], "finance")

    finance =
      build_conn()
      |> put_bearer_token(owner)
      |> get("/api/org/#{organization.slug}/admin/users/#{owner.id}/finance")
      |> json_response(200)

    assert finance["available"] == false

    both =
      build_conn()
      |> put_bearer_token(owner)
      |> get("/api/org/#{organization.slug}/admin/users/#{coach_member.id}")
      |> json_response(200)
      |> get_in(["user"])

    assert both["identity"]["role"] == "coach"
    assert "finance" in both["available_sections"]
  end

  test "the cleanup removes staff-only profiles without money and keeps the rest", %{
    owner: owner,
    coach: coach,
    member: member,
    context: context
  } do
    # Legacy rows written straight to the store, as the old ledger did.
    {:ok, owner_profile} = Finance.upsert_membership(context, owner.id, legacy_params())
    {:ok, coach_profile} = Finance.upsert_membership(context, coach.id, legacy_params())
    {:ok, member_profile} = Finance.upsert_membership(context, member.id, legacy_params())

    {:ok, _payment} =
      Finance.record_payment(context, coach_profile.id, %{
        amount_cents: 1000,
        payment_method: "cash",
        payment_status: "paid"
      })

    migration = Palee.Repo.Migrations.RemoveStaffFinanceProfiles

    unless Code.ensure_loaded?(migration) do
      Code.require_file(
        "repo/migrations/20261227100000_remove_staff_finance_profiles.exs",
        :code.priv_dir(:palee)
      )
    end

    Repo.query!(apply(migration, :cleanup_sql, []))

    ids =
      Repo.query!("SELECT id FROM memberships").rows
      |> List.flatten()
      |> Enum.map(&Ecto.UUID.cast!/1)

    refute owner_profile.id in ids
    assert coach_profile.id in ids
    assert member_profile.id in ids
  end

  defp legacy_params,
    do: %{user_type_snapshot: "member", status: "trial", signup_source: "admin_created"}

  defp join(organization, user, roles) do
    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        roles: roles,
        status: :active,
        joined_at: DateTime.utc_now()
      })
  end
end
