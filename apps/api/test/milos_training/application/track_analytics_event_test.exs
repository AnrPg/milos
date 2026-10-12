defmodule MilosTraining.Application.TrackAnalyticsEventTest do
  @moduledoc "ADR-105: best-effort, tenant-scoped instrumentation helper."
  use MilosTraining.DataCase, async: false

  import MilosTraining.AnalyticsHelpers

  alias MilosTraining.Application.{CreateDraftWorkout, RecordAnalyticsEvent, TrackAnalyticsEvent}

  defmodule FailingAnalyticsStore do
    @moduledoc false
    def record_event(_params), do: raise("analytics store unavailable")
    def record_events(_params), do: raise("analytics store unavailable")
  end

  test "records with the explicit tenant even outside any tenant session" do
    {organization, owner, _context} = organization_fixture()

    assert :ok =
             TrackAnalyticsEvent.call("class_slot_cancelled", nil, %{id: Ecto.UUID.generate()}, %{
               organization_id: organization.id,
               user_id: owner.id
             })

    event = analytics_event!(organization.id, "class_slot_cancelled")
    assert event.user_id == owner.id
    assert event.context_type == "scheduled_class"
  end

  test "unknown event names never raise and record nothing" do
    {organization, _owner, context} = organization_fixture()
    assert :ok = TrackAnalyticsEvent.call("no_such_event", context, %{id: Ecto.UUID.generate()})
    assert analytics_events(organization.id, "no_such_event") == []
  end

  test "RecordAnalyticsEvent.call/2 rejects unregistered names" do
    {organization, _owner, _context} = organization_fixture()

    assert {:error, :unknown_analytics_event} =
             RecordAnalyticsEvent.call("no_such_event", %{organization_id: organization.id})
  end

  describe "analytics write failure" do
    setup do
      previous = Application.get_env(:milos_training, :analytics_store)
      Application.put_env(:milos_training, :analytics_store, FailingAnalyticsStore)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:milos_training, :analytics_store, previous),
          else: Application.delete_env(:milos_training, :analytics_store)
      end)
    end

    test "does not fail the instrumented operation" do
      {organization, owner, context} = organization_fixture()

      assert {:ok, draft} = CreateDraftWorkout.call(context, owner)
      assert is_binary(draft.id)
      assert analytics_events(organization.id, "workout_created") == []
    end
  end
end
