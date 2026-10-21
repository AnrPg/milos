defmodule Palee.Application.SetHomeLocationTest do
  use Palee.DataCase, async: false

  alias Palee.Application.SetHomeLocation
  alias Palee.{Facility, Organizations}

  import Palee.TestFixtures

  setup do
    {:ok, organization} = Organizations.ensure_legacy_organization_for_migration()
    Repo.query!("SELECT set_config($1, $2, false)", ["app.organization_id", organization.id])

    owner = admin_fixture()
    owner_context = tenant_context(owner, :owner)
    {:ok, kypseli} = Facility.create_location(owner_context, %{name: "Κυψέλη"})
    {:ok, patisia} = Facility.create_location(owner_context, %{name: "Πατήσια"})

    %{owner_context: owner_context, kypseli: kypseli, patisia: patisia}
  end

  defp tenant_context(actor, role \\ nil) do
    {:ok, _membership} = Organizations.ensure_legacy_membership_for_migration(actor, role)

    {:ok, context} =
      Organizations.resolve_tenant_context(actor, Organizations.legacy_organization_slug())

    context
  end

  defp home(context, user_id),
    do: Organizations.membership_summary(context.organization_id, user_id).home_location_id

  test "a member sets and clears their own home location", %{kypseli: kypseli} do
    member = user_fixture()
    context = tenant_context(member)

    assert {:ok, membership} = SetHomeLocation.call(context, member.id, kypseli.id)
    assert membership.home_location_id == kypseli.id
    assert home(context, member.id) == kypseli.id

    assert {:ok, membership} = SetHomeLocation.call(context, member.id, nil)
    assert membership.home_location_id == nil
  end

  test "only staff who manage memberships set someone else's", %{
    owner_context: owner_context,
    patisia: patisia
  } do
    member = user_fixture()
    other = user_fixture()
    member_context = tenant_context(member)
    _other_context = tenant_context(other)

    assert {:error, :forbidden} = SetHomeLocation.call(member_context, other.id, patisia.id)
    assert {:ok, _membership} = SetHomeLocation.call(owner_context, other.id, patisia.id)
    assert home(owner_context, other.id) == patisia.id
  end

  test "an archived or unknown location is refused", %{
    owner_context: owner_context,
    patisia: patisia
  } do
    member = user_fixture()
    context = tenant_context(member)
    {:ok, _archived} = Facility.archive_location(owner_context, patisia.id)

    assert {:error, [location_id: _]} = SetHomeLocation.call(context, member.id, patisia.id)

    assert {:error, [location_id: _]} =
             SetHomeLocation.call(context, member.id, Ecto.UUID.generate())

    assert {:error, [location_id: _]} = SetHomeLocation.call(context, member.id, "not-a-uuid")
  end
end
