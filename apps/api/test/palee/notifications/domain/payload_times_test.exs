defmodule Palee.Notifications.Domain.PayloadTimesTest do
  use ExUnit.Case, async: true

  alias Palee.Notifications.Domain.PayloadTimes

  def localize(message, bindings),
    do: Enum.reduce(bindings, message, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", v) end)

  @localize &__MODULE__.localize/2

  test "writes every moment on the organiser's clock, adding the reader's when it differs" do
    payload = %{
      "class_starts_at" => "2026-10-24T16:00:00Z",
      "class_when" => "stale",
      "scanned_at" => "2026-10-24T05:00:00Z"
    }

    assert %{
             "class_when" => "24/10 19:00 Athens · 17:00 your time",
             "scanned_when" => "08:00 Athens · 06:00 your time"
           } = PayloadTimes.localize(payload, "Europe/Athens", "Europe/London", @localize)

    assert %{"class_when" => "24/10 19:00"} =
             PayloadTimes.localize(payload, "Europe/Athens", "Europe/Athens", @localize)
  end

  test "an appointment's start gets a text instead of a raw timestamp" do
    assert %{"starts_when" => "24/10 19:00"} =
             PayloadTimes.localize(
               %{"starts_at" => "2026-10-24T16:00:00Z"},
               "Europe/Athens",
               nil,
               @localize
             )
  end

  test "without an organiser zone a producer's text is kept, a missing one is written in UTC" do
    assert %{"event_when" => "kept"} =
             PayloadTimes.localize(
               %{"event_starts_at" => "2026-10-24T16:00:00Z", "event_when" => "kept"},
               nil,
               "Europe/London",
               @localize
             )

    assert %{"starts_when" => "24/10 16:00 UTC"} =
             PayloadTimes.localize(%{"starts_at" => "2026-10-24T16:00:00Z"}, nil, nil, @localize)
  end

  test "mentions_moment?/1" do
    assert PayloadTimes.mentions_moment?(%{"event_starts_at" => "2026-10-24T16:00:00Z"})
    refute PayloadTimes.mentions_moment?(%{"title" => "hi"})
  end
end
