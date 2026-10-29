defmodule PaleeWeb.BoxScreenSocketTest do
  @moduledoc """
  ADR-253: the box screen's socket takes only a display token; the screen
  joins its box's topic and the timers of its classes, hears refresh hints
  (never who) from bookings, attendance, cancellations, schedule changes and
  new results, hears its own override only, and is disconnected when it is
  removed or moved to another TV.
  """

  use PaleeWeb.ConnCase, async: false

  import Palee.TestFixtures
  require Phoenix.ChannelTest

  alias Palee.{BoxScreens, Organizations}
  alias Palee.Application.BoxScreens.{BoxScreenAdmin, BoxScreenDisplay}
  alias Palee.Application.CompleteWorkout
  alias Palee.Infrastructure.Auth.Guardian
  alias PaleeWeb.{BoxScreenChannel, BoxScreenSocket, BoxScreenTimerChannel}

  @endpoint PaleeWeb.Endpoint

  setup do
    owner = admin_fixture()
    {:ok, _} = Organizations.ensure_legacy_membership_for_migration(owner, :owner)

    {:ok, context} =
      Organizations.resolve_tenant_context(owner, Organizations.legacy_organization_slug())

    %{owner: owner, context: context}
  end

  defp paired_screen(context, params \\ %{"name" => "TV"}) do
    {:ok, %{screen: %{id: id}, pairing_code: %{code: code}}} =
      BoxScreenAdmin.create(context, params)

    {:ok, %{token: token}} = BoxScreenDisplay.pair(%{"code" => code})
    {id, token}
  end

  defp join_box(token, organization_id) do
    {:ok, socket} = Phoenix.ChannelTest.connect(BoxScreenSocket, %{"token" => token})

    {:ok, _reply, socket} =
      Phoenix.ChannelTest.subscribe_and_join(
        socket,
        BoxScreenChannel,
        "box_screen:#{organization_id}"
      )

    socket
  end

  test "only a display token connects, and only to its own box", ctx do
    {_id, token} = paired_screen(ctx.context)

    assert :error = Phoenix.ChannelTest.connect(BoxScreenSocket, %{"token" => "nope"})
    assert :error = Phoenix.ChannelTest.connect(BoxScreenSocket, %{})

    {:ok, user_token, _claims} =
      Guardian.encode_and_sign(ctx.owner, %{"sv" => ctx.owner.security_version || 1},
        token_type: "access"
      )

    assert :error = Phoenix.ChannelTest.connect(BoxScreenSocket, %{"token" => user_token})

    {:ok, socket} = Phoenix.ChannelTest.connect(BoxScreenSocket, %{"token" => token})

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               BoxScreenChannel,
               "box_screen:#{Ecto.UUID.generate()}"
             )

    # The person's socket has no box-screen topic at all.
    {:ok, user_socket} =
      Phoenix.ChannelTest.connect(PaleeWeb.UserSocket, %{
        "token" => user_token,
        "organization_slug" => Organizations.legacy_organization_slug()
      })

    assert_raise RuntimeError, ~r/no channel found/, fn ->
      Phoenix.ChannelTest.subscribe_and_join(
        user_socket,
        "box_screen:#{ctx.context.organization_id}",
        %{}
      )
    end
  end

  test "the box's events send refresh hints that never say who", ctx do
    {_id, token} = paired_screen(ctx.context)
    organization_id = ctx.context.organization_id
    join_box(token, organization_id)
    slot_id = Ecto.UUID.generate()

    for {event, kind} <- [
          {:booking_made, "booking"},
          {:booking_cancelled, "booking"},
          {:attendance_recorded, "attendance"},
          {:class_cancelled, "class_cancelled"}
        ] do
      Palee.DomainEvents.publish(event, %{
        organization_id: organization_id,
        scheduled_class_id: slot_id,
        user_id: ctx.owner.id,
        booking_id: Ecto.UUID.generate(),
        at: DateTime.utc_now()
      })

      Phoenix.ChannelTest.assert_push("box_screen:refresh", payload)
      assert payload == %{kind: kind, slot_id: slot_id}
    end

    CompleteWorkout.publish_result(
      %{organization_id: organization_id, master_workout_id: Ecto.UUID.generate()},
      DateTime.utc_now()
    )

    Phoenix.ChannelTest.assert_push("box_screen:refresh", %{kind: "result", slot_id: nil})

    Phoenix.PubSub.broadcast(
      Palee.PubSub,
      "schedule:slot_updated",
      {:schedule_slot_updated, %{id: slot_id, organization_id: organization_id}}
    )

    Phoenix.ChannelTest.assert_push("box_screen:refresh", %{kind: "schedule", slot_id: ^slot_id})

    # Another box's events stay there.
    Palee.DomainEvents.publish(:booking_made, %{
      organization_id: Ecto.UUID.generate(),
      scheduled_class_id: slot_id
    })

    Phoenix.ChannelTest.refute_push("box_screen:refresh", _payload)
  end

  test "an override reaches its own screen only", ctx do
    {id, token} = paired_screen(ctx.context)
    {other_id, other_token} = paired_screen(ctx.context, %{"name" => "Other"})
    organization_id = ctx.context.organization_id

    join_box(token, organization_id)

    assert {:ok, _result} = BoxScreenAdmin.put_override(ctx.context, other_id, %{"view" => "wod"})
    Phoenix.ChannelTest.assert_push("box_screen:refresh", %{kind: "override"})
    Phoenix.ChannelTest.refute_push("box_screen:override", _payload)

    assert {:ok, _result} =
             BoxScreenAdmin.put_override(ctx.context, id, %{"view" => "bookings"})

    Phoenix.ChannelTest.assert_push("box_screen:override", %{
      override: %{view: "bookings", slot_id: nil, until: nil}
    })

    assert {:ok, _result} = BoxScreenAdmin.delete_override(ctx.context, id)
    Phoenix.ChannelTest.assert_push("box_screen:override", %{override: nil})

    assert other_token != token
  end

  test "removing or re-pairing a screen closes its socket", ctx do
    {id, _token} = paired_screen(ctx.context)
    @endpoint.subscribe(BoxScreenSocket.socket_id(id))

    {:ok, %{pairing_code: %{code: code}}} = BoxScreenAdmin.pairing_code(ctx.context, id)
    {:ok, _paired} = BoxScreenDisplay.pair(%{"code" => code})
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}

    :ok = BoxScreenAdmin.delete(ctx.context, id)
    assert_receive %Phoenix.Socket.Broadcast{event: "disconnect"}
    assert nil == BoxScreens.get(ctx.context, id)
  end

  test "the screen follows the timers of the classes it shows", ctx do
    {:ok, kypseli} = Palee.Facility.create_location(ctx.context, %{name: "Κυψέλη"})
    {:ok, patisia} = Palee.Facility.create_location(ctx.context, %{name: "Πατήσια"})
    {_id, token} = paired_screen(ctx.context, %{"name" => "TV", "location_id" => kypseli.id})

    workout = workout_fixture(ctx.owner, %{tenant_context: ctx.context})
    ours = slot_fixture(workout, %{tenant_context: ctx.context})
    theirs = slot_fixture(workout, %{tenant_context: ctx.context})

    Palee.Repo.query!("UPDATE scheduled_classes SET location_id = $1 WHERE id = $2", [
      Ecto.UUID.dump!(patisia.id),
      Ecto.UUID.dump!(theirs.id)
    ])

    {:ok, socket} = Phoenix.ChannelTest.connect(BoxScreenSocket, %{"token" => token})

    assert {:ok, _reply, _socket} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               BoxScreenTimerChannel,
               "class_timer:#{ours.id}"
             )

    PaleeWeb.Realtime.broadcast_class_timer(ours.id, %{timer: %{status: "running"}})
    Phoenix.ChannelTest.assert_push("class_timer:updated", %{timer: %{status: "running"}})

    assert {:error, %{reason: "unauthorized"}} =
             Phoenix.ChannelTest.subscribe_and_join(
               socket,
               BoxScreenTimerChannel,
               "class_timer:#{theirs.id}"
             )
  end
end
