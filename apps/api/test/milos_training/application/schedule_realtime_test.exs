defmodule MilosTraining.Application.ScheduleRealtimeTest do
  use MilosTraining.DataCase, async: false

  import ExUnit.CaptureLog

  alias MilosTraining.Application.ScheduleRealtime
  alias MilosTraining.Organizations
  alias MilosTraining.TestFixtures

  test "broadcasts to the payload's own organization topic, not the legacy organization" do
    owner = TestFixtures.admin_fixture()
    {:ok, organization} = Organizations.create_organization(%{name: "Schedule Realtime Gym"})

    {:ok, _membership} =
      Organizations.add_membership(%{
        organization_id: organization.id,
        user_id: owner.id,
        role: :owner,
        status: :active,
        joined_at: DateTime.utc_now()
      })

    legacy_organization =
      Organizations.get_by_slug(Organizations.legacy_organization_slug())

    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:#{organization.id}")
    Phoenix.PubSub.subscribe(MilosTraining.PubSub, "schedule:#{legacy_organization.id}")

    ScheduleRealtime.broadcast("slot_created", %{
      organization_id: organization.id,
      slot_id: "some-slot-id"
    })

    assert_receive %Phoenix.Socket.Broadcast{
      topic: topic,
      event: "schedule:refresh",
      payload: %{event: "slot_created"}
    }

    assert topic == "schedule:#{organization.id}"

    legacy_topic = "schedule:#{legacy_organization.id}"
    refute_received %Phoenix.Socket.Broadcast{topic: ^legacy_topic}
  end

  test "logs a warning instead of silently falling back when organization_id is missing" do
    log =
      capture_log(fn ->
        ScheduleRealtime.broadcast("slot_created", %{slot_id: "some-slot-id"})
      end)

    assert log =~ "omitted organization_id"
  end
end
