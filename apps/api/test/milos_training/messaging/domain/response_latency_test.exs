defmodule MilosTraining.Messaging.Domain.ResponseLatencyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Messaging.Domain.ResponseLatency

  defp message(seq, sender, seconds, type \\ :chat) do
    %{
      id: "m#{seq}",
      sequence_number: seq,
      sender_id: sender,
      message_type: type,
      inserted_at: DateTime.add(~U[2026-10-12 09:00:00Z], seconds, :second)
    }
  end

  test "measures from the oldest unanswered member message, ignoring system messages" do
    history = [
      message(1, "coach", 0),
      message(2, "member", 60),
      message(3, "member", 120),
      message(4, "bot", 150, :system)
    ]

    reply = message(5, "coach", 660)

    assert ResponseLatency.first_staff_response(history ++ [reply], reply, ["coach"]) == %{
             response_latency_seconds: 600,
             pending_member_message_count: 2
           }
  end

  test "is nil for member senders, follow-up staff messages and empty threads" do
    assert ResponseLatency.first_staff_response([], message(1, "coach", 0), ["coach"]) == nil

    assert ResponseLatency.first_staff_response(
             [message(1, "member", 0)],
             message(2, "member", 5),
             ["coach"]
           ) == nil

    assert ResponseLatency.first_staff_response(
             [message(1, "member", 0), message(2, "coach", 5)],
             message(3, "coach", 9),
             ["coach"]
           ) == nil
  end
end
