defmodule Palee.Application.QrCheckInRLSTest do
  @moduledoc """
  ADR-155 under real Row Level Security: a door resolves its box before any
  tenant is known (definer lookup), a scan checks in through the tenant
  policies, and visitor scans, check-in rules, member codes and Wallet cards
  never cross boxes.
  """

  use Palee.DataCase, async: false

  @moduletag :rls_enforced

  import Palee.TestFixtures

  alias Palee.Application.{DoorDisplay, MemberCodes, ScanCheckIn, UpdateCheckInRules}
  alias Palee.{Facility, Organizations, Wallet}

  setup do
    bypass_rls(fn ->
      {:ok, gym} = Organizations.create_organization(%{name: "RLS Door Gym"})
      {:ok, other} = Organizations.create_organization(%{name: "RLS Other Gym"})
      owner = user_fixture()
      other_owner = user_fixture()
      member = user_fixture()
      outsider = user_fixture()
      add!(gym, owner, :owner)
      add!(other, other_owner, :owner)
      add!(gym, member, :member)
      add!(other, outsider, :member)

      %{
        gym: gym,
        other: other,
        owner: owner,
        other_owner: other_owner,
        member: member,
        outsider: outsider
      }
    end)
    |> then(fn fixtures ->
      Map.merge(fixtures, %{
        ctx: tenant!(fixtures.owner, fixtures.gym),
        other_ctx: tenant!(fixtures.other_owner, fixtures.other)
      })
    end)
  end

  test "a door scan resolves the box, checks in, and records visitors per box", ctx do
    {:ok, location} = Facility.create_location(ctx.ctx, %{name: "Door"})
    {:ok, _rules} = UpdateCheckInRules.call(ctx.ctx, %{open_gym_requires_package: false})

    assert %{organization_id: gym_id, location_name: "Door"} = Facility.door_location(location.id)
    assert gym_id == ctx.gym.id

    {:ok, display} = DoorDisplay.show(ctx.ctx, location.id)

    assert {:ok, %{outcome: "checked_in", check_in: %{kind: "open_gym", method: "door_qr"}}} =
             ScanCheckIn.scan(ctx.member, %{location_id: location.id, code: display.code})

    assert {:ok, %{outcome: "visitor", membership: "none"}} =
             ScanCheckIn.scan(ctx.outsider, %{location_id: location.id, code: display.code})

    assert [%{user_id: visitor_id}] = Facility.list_visitor_scans(ctx.ctx)
    assert visitor_id == ctx.outsider.id
    assert [] = Facility.list_visitor_scans(ctx.other_ctx)

    # The other box cannot read this location's door.
    assert {:error, :location_not_found} = DoorDisplay.show(ctx.other_ctx, location.id)
    assert Facility.check_in_rules(ctx.other_ctx).open_gym_requires_package == true
  end

  test "member codes and Wallet cards stay in their box", ctx do
    {:ok, _rules} = UpdateCheckInRules.call(ctx.ctx, %{member_code_mode: "static"})
    member_ctx = tenant!(ctx.member, ctx.gym)

    assert {:ok, %{mode: "static", code: "S1" <> _ = code}} = MemberCodes.current(member_ctx)
    assert {:ok, user_id, "member_qr"} = MemberCodes.resolve(ctx.ctx, code, DateTime.utc_now())
    assert user_id == ctx.member.id

    # The other box neither knows the code nor accepts it.
    assert {:error, _} = MemberCodes.resolve(ctx.other_ctx, code, DateTime.utc_now())

    {:ok, record} = MemberCodes.ensure(member_ctx, ctx.member.id)
    assert nil == Facility.get_member_code_by_serial(ctx.other_ctx, record.serial)

    serial = Ecto.UUID.generate()

    {:ok, pass} =
      Wallet.create_pass(member_ctx, %{
        user_id: ctx.member.id,
        member_code_id: record.id,
        platform: "apple",
        serial: serial,
        auth_token_hash: :crypto.hash(:sha256, "token"),
        last_updated_at: DateTime.utc_now()
      })

    assert Wallet.get_pass(ctx.ctx, pass.id)
    assert nil == Wallet.get_pass(ctx.other_ctx, pass.id)
    assert [%{id: id}] = Wallet.list_user_passes(%{user_id: ctx.member.id})
    assert id == pass.id
    assert [] = Wallet.list_user_passes(%{user_id: ctx.outsider.id})

    # PassKit lookups carry only a serial: the definer finds the box.
    assert Wallet.pass_organization(serial) == ctx.gym.id

    {:ok, _counts} = MemberCodes.revoke(ctx.ctx, ctx.member.id, "staff")
    refute is_nil(Wallet.get_pass(ctx.ctx, pass.id).revoked_at)
  end

  defp add!(organization, user, role) do
    {:ok, membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: user.id,
        role: role,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    membership
  end

  defp tenant!(user, organization) do
    {:ok, context} = Organizations.resolve_tenant_context(user, organization.slug)
    context
  end
end
