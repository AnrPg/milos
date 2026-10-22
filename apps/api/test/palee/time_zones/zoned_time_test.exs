defmodule Palee.TimeZones.ZonedTimeTest do
  use ExUnit.Case, async: true

  alias Palee.TimeZones.ZonedTime

  @localize &__MODULE__.localize/2

  def localize(message, bindings),
    do: Enum.reduce(bindings, message, fn {k, v}, acc -> String.replace(acc, "%{#{k}}", v) end)

  # 24 Oct 2026, 16:00 UTC: 19:00 in Athens (EEST, +3), 17:00 in London (BST, +1).
  @summer ~U[2026-10-24 16:00:00Z]
  # 3 Nov 2026, 17:00 UTC: 19:00 in Athens (EET, +2), 17:00 in London (GMT).
  @winter ~U[2026-11-03 17:00:00Z]

  test "valid?/1 and utc?/1" do
    assert ZonedTime.valid?("Europe/Athens")
    refute ZonedTime.valid?("Mars/Olympus")
    refute ZonedTime.valid?(nil)
    assert ZonedTime.utc?("Etc/UTC")
    refute ZonedTime.utc?("Europe/London")
  end

  test "parse/1 reads DateTimes and ISO strings" do
    assert ZonedTime.parse(@summer) == @summer
    assert ZonedTime.parse("2026-10-24T16:00:00Z") == @summer
    assert ZonedTime.parse("tomorrow") == nil
    assert ZonedTime.parse(nil) == nil
  end

  test "label/1 is the zone's city" do
    assert ZonedTime.label("Europe/Athens") == "Athens"
    assert ZonedTime.label("America/Argentina/Buenos_Aires") == "Buenos Aires"
    assert ZonedTime.label("Etc/UTC") == "UTC"
  end

  test "same_clock?/3 compares offsets at that moment" do
    assert ZonedTime.same_clock?(@summer, "Europe/Athens", "Europe/Bucharest")
    refute ZonedTime.same_clock?(@summer, "Europe/Athens", "Europe/London")
    refute ZonedTime.same_clock?(@summer, "Europe/Athens", "Mars/Olympus")
  end

  test "format/3 writes the zone's wall clock, UTC marked when unknown" do
    assert ZonedTime.format(@summer, "Europe/Athens") == "24/10 19:00"
    assert ZonedTime.format(@winter, "Europe/Athens") == "03/11 19:00"
    assert ZonedTime.format(@summer, "Europe/Athens", :time) == "19:00"
    assert ZonedTime.format(@summer, nil) == "24/10 16:00 UTC"
  end

  describe "format_for/5" do
    test "plain when the reader reads the moment alike, or is unknown" do
      assert ZonedTime.format_for(@summer, "Europe/Athens", "Europe/Athens", @localize) ==
               "24/10 19:00"

      assert ZonedTime.format_for(@summer, "Europe/Athens", "Europe/Bucharest", @localize) ==
               "24/10 19:00"

      assert ZonedTime.format_for(@summer, "Europe/Athens", nil, @localize) == "24/10 19:00"
    end

    test "adds the reader's own time when their clock differs" do
      assert ZonedTime.format_for(@summer, "Europe/Athens", "Europe/London", @localize) ==
               "24/10 19:00 Athens · 17:00 your time"
    end

    test "repeats the date when the reader's day differs" do
      assert ZonedTime.format_for(@summer, "Europe/Athens", "Asia/Tokyo", @localize) ==
               "24/10 19:00 Athens · 25/10 01:00 your time"
    end

    test "time-only moments stay time-only" do
      assert ZonedTime.format_for(@summer, "Europe/Athens", "Asia/Tokyo", @localize, :time) ==
               "19:00 Athens · 01:00 your time"
    end
  end

  describe "to_utc/3 and start_of_day/2" do
    test "reads a wall-clock time on the zone, across DST" do
      assert ZonedTime.to_utc(~D[2026-10-24], ~T[19:00:00], "Europe/Athens") == @summer
      assert ZonedTime.to_utc(~D[2026-11-03], ~T[19:00:00], "Europe/Athens") == @winter
    end

    test "a skipped time moves past the jump; a repeated one takes the first" do
      # Athens jumps 03:00 -> 04:00 on 29 Mar 2026 and repeats 03:00-04:00 on 25 Oct 2026.
      assert ZonedTime.to_utc(~D[2026-03-29], ~T[03:30:00], "Europe/Athens") ==
               ~U[2026-03-29 01:00:00Z]

      assert ZonedTime.to_utc(~D[2026-10-25], ~T[03:30:00], "Europe/Athens") ==
               ~U[2026-10-25 00:30:00Z]
    end

    test "the gym's midnight" do
      assert ZonedTime.start_of_day(~D[2026-10-24], "Europe/Athens") == ~U[2026-10-23 21:00:00Z]
      assert ZonedTime.local_date(~U[2026-10-23 21:30:00Z], "Europe/Athens") == ~D[2026-10-24]
    end
  end
end
