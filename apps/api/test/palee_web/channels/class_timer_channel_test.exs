defmodule PaleeWeb.ClassTimerChannelTest do
  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  require Phoenix.ChannelTest

  alias Palee.{Identity, Organizations}
  alias Palee.Infrastructure.Auth.Guardian
  alias PaleeWeb.{ClassTimerChannel, UserSocket}

  @endpoint PaleeWeb.Endpoint

  setup do
    admin = user_fixture()
    {:ok, admin} = Identity.update_role(admin, :admin)
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(admin, :owner)

    {:ok, context} =
      Organizations.resolve_tenant_context(admin, Organizations.legacy_organization_slug())

    slot =
      slot_fixture(workout_fixture(admin, %{tenant_context: context}), %{tenant_context: context})

    {:ok, slot: slot}
  end

  defp socket_for(user, slug) do
    {:ok, token, _claims} =
      Guardian.encode_and_sign(user, %{"sv" => user.security_version || 1}, token_type: "access")

    Phoenix.ChannelTest.connect(UserSocket, %{"token" => token, "organization_slug" => slug})
  end

  test "gym members can follow a class timer and receive its updates", %{slot: slot} do
    member = user_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(member)
    {:ok, socket} = socket_for(member, Organizations.legacy_organization_slug())

    assert {:ok, _reply, _socket} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               ClassTimerChannel,
               "class_timer:#{slot.id}"
             )

    PaleeWeb.Realtime.broadcast_class_timer(slot.id, %{timer: %{status: "running"}})
    Phoenix.ChannelTest.assert_push("class_timer:updated", %{timer: %{status: "running"}})
  end

  test "people outside the gym cannot join", %{slot: slot} do
    outsider = user_fixture()

    {:ok, other} =
      Organizations.create_organization(%{
        name: "Other Gym #{System.unique_integer([:positive])}"
      })

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: other.id,
        user_id: outsider.id,
        role: :member,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    {:ok, socket} = socket_for(outsider, other.slug)

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               ClassTimerChannel,
               "class_timer:#{slot.id}"
             )
  end
end
