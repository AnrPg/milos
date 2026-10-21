defmodule Palee.Analytics.Domain.ExecutionInteractionTest do
  use ExUnit.Case, async: true

  alias Palee.Analytics.Domain.ExecutionInteraction

  @now ~U[2026-10-12 10:00:00.000000Z]

  defp event(attrs \\ %{}) do
    Map.merge(
      %{
        "client_event_id" => Ecto.UUID.generate(),
        "kind" => "pause",
        "occurred_at" => "2026-10-12T09:59:30Z",
        "metadata" => %{"segment_index" => 3, "format" => "amrap", "surface" => "pause_sheet"}
      },
      attrs
    )
  end

  test "kinds cover the timer audit surfaces" do
    for kind <- ~w(pause resume segment_skipped segment_restarted round_incremented
                   round_decremented time_adjusted rounds_adjusted ready_screen_shown
                   workout_launched first_segment_started finish_wizard_opened
                   finish_wizard_saved finish_wizard_abandoned cast_mode_toggled) do
      assert kind in ExecutionInteraction.kinds()
    end
  end

  test "a valid batch normalizes events and collapses in-batch duplicates" do
    first = event()
    id = first["client_event_id"]

    assert {:ok, [normalized]} =
             ExecutionInteraction.validate_batch(
               [first, Map.put(event(), "client_event_id", id)],
               @now
             )

    assert normalized.kind == "pause"
    assert normalized.client_event_id == id
    assert normalized.occurred_at == ~U[2026-10-12 09:59:30.000000Z]

    assert normalized.metadata == %{
             "segment_index" => 3,
             "format" => "amrap",
             "surface" => "pause_sheet"
           }
  end

  test "atom-keyed events are accepted" do
    assert {:ok, [_]} =
             ExecutionInteraction.validate_batch(
               [
                 %{
                   client_event_id: Ecto.UUID.generate(),
                   kind: "round_incremented",
                   occurred_at: @now,
                   metadata: %{round_count: 4}
                 }
               ],
               @now
             )
  end

  test "unknown kinds reject the whole batch with the offending index" do
    assert {:error, {:invalid_execution_interactions, [%{index: 1, reason: :unknown_kind}]}} =
             ExecutionInteraction.validate_batch([event(), event(%{"kind" => "dance"})], @now)
  end

  test "metadata outside the kind's typed allowlist is rejected" do
    assert {:error, {:invalid_execution_interactions, [%{reason: :metadata_field_not_allowed}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"metadata" => %{"note" => "free text"}})],
               @now
             )

    assert {:error, {:invalid_execution_interactions, [%{reason: :metadata_field_not_allowed}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"metadata" => %{"delta_seconds" => 30}})],
               @now
             )

    assert {:error, {:invalid_execution_interactions, [%{reason: :invalid_metadata_value}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"kind" => "time_adjusted", "metadata" => %{"delta_seconds" => 99_999}})],
               @now
             )

    assert {:error, {:invalid_execution_interactions, [%{reason: :invalid_metadata_value}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"metadata" => %{"surface" => "somewhere"}})],
               @now
             )
  end

  test "client ids, timestamps and batch size are enforced" do
    assert {:error, {:invalid_execution_interactions, [%{reason: :invalid_client_event_id}]}} =
             ExecutionInteraction.validate_batch([event(%{"client_event_id" => "1"})], @now)

    assert {:error, {:invalid_execution_interactions, [%{reason: :occurred_at_out_of_range}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"occurred_at" => "2026-09-01T00:00:00Z"})],
               @now
             )

    assert {:error, {:invalid_execution_interactions, [%{reason: :occurred_at_out_of_range}]}} =
             ExecutionInteraction.validate_batch(
               [event(%{"occurred_at" => "2026-10-12T11:00:00Z"})],
               @now
             )

    too_many = Enum.map(1..(ExecutionInteraction.max_batch() + 1), fn _ -> event() end)

    assert {:error, {:invalid_execution_interactions, [%{reason: :batch_too_large}]}} =
             ExecutionInteraction.validate_batch(too_many, @now)

    assert {:error, {:invalid_execution_interactions, [%{reason: :empty_batch}]}} =
             ExecutionInteraction.validate_batch([], @now)
  end
end
