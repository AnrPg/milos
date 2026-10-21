defmodule Palee.Places.Domain.WhenWindowTest do
  use ExUnit.Case, async: true

  alias Palee.Places.Domain.WhenWindow

  @tz "Europe/Athens"

  defp windows(when_, times, now, from \\ nil, to \\ nil),
    do: WhenWindow.windows(when_, from, to, times, now, @tz)

  test "nothing chosen means no window" do
    assert windows(nil, [], ~U[2026-10-21 10:00:00Z]) == nil
  end

  test "today is the local day, from local midnight to local midnight" do
    # 01:30 in Athens on 22 October is still 21 October in UTC.
    assert [{~U[2026-10-21 21:00:00Z], ~U[2026-10-22 21:00:00Z]}] =
             windows("today", [], ~U[2026-10-21 22:30:00Z])
  end

  test "the weekend is the coming Saturday and Sunday, merged into one window" do
    # Wednesday 21 October 2026; Sunday 25 October is the day clocks go back.
    assert [{~U[2026-10-23 21:00:00Z], ~U[2026-10-25 22:00:00Z]}] =
             windows("weekend", [], ~U[2026-10-21 10:00:00Z])

    # On Saturday it is today and tomorrow; on Sunday only today.
    assert [{~U[2026-10-23 21:00:00Z], _}] = windows("weekend", [], ~U[2026-10-24 10:00:00Z])

    assert [{~U[2026-10-24 21:00:00Z], ~U[2026-10-25 22:00:00Z]}] =
             windows("weekend", [], ~U[2026-10-25 10:00:00Z])
  end

  test "the day clocks go back has 25 hours and its evening keeps its wall-clock times" do
    now = ~U[2026-10-25 08:00:00Z]
    [{from, to}] = windows("today", [], now)
    assert DateTime.diff(to, from, :hour) == 25

    # 17:00–24:00 local is 15:00–22:00 UTC after the change (EET, +2).
    assert [{~U[2026-10-25 15:00:00Z], ~U[2026-10-25 22:00:00Z]}] =
             windows("today", ["evening"], now)

    # The day before, still summer time (+3).
    assert [{~U[2026-10-24 14:00:00Z], ~U[2026-10-24 21:00:00Z]}] =
             windows("today", ["evening"], ~U[2026-10-24 08:00:00Z])
  end

  test "the day clocks go forward has 23 hours and its morning keeps its wall-clock times" do
    now = ~U[2027-03-28 08:00:00Z]
    [{from, to}] = windows("today", [], now)
    assert DateTime.diff(to, from, :hour) == 23

    # 05:00–12:00 local in summer time (+3) is 02:00–09:00 UTC.
    assert [{~U[2027-03-28 02:00:00Z], ~U[2027-03-28 09:00:00Z]}] =
             windows("today", ["morning"], now)

    # A morning across the weekend of the change: Saturday +2, Sunday +3.
    assert [
             {~U[2027-03-27 03:00:00Z], ~U[2027-03-27 10:00:00Z]},
             {~U[2027-03-28 02:00:00Z], ~U[2027-03-28 09:00:00Z]}
           ] = windows("weekend", ["morning"], ~U[2027-03-24 10:00:00Z])
  end

  test "parts of the day are separate windows; touching ones merge" do
    now = ~U[2026-10-21 10:00:00Z]

    assert [{~U[2026-10-22 02:00:00Z], ~U[2026-10-22 09:00:00Z]}, {evening, _}] =
             windows("tomorrow", ["morning", "evening"], now)

    assert evening == ~U[2026-10-22 14:00:00Z]

    assert [{~U[2026-10-22 02:00:00Z], ~U[2026-10-22 14:00:00Z]}] =
             windows("tomorrow", ["morning", "midday"], now)
  end

  test "a range covers its days inclusively; parts without days cover two weeks" do
    assert [{~U[2026-11-01 22:00:00Z], ~U[2026-11-04 22:00:00Z]}] =
             windows("range", [], ~U[2026-10-21 10:00:00Z], ~D[2026-11-02], ~D[2026-11-04])

    assert length(windows(nil, ["evening"], ~U[2026-10-21 10:00:00Z])) == 14
    assert [_one] = windows("week", [], ~U[2026-10-21 10:00:00Z])
  end
end
