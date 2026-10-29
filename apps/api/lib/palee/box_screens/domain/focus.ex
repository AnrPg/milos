defmodule Palee.BoxScreens.Domain.Focus do
  @moduledoc """
  What a box screen puts first right now (ADR-253), pure.

  Automatically (`source: "auto"`), from today's classes on the box's clock:

    * `timer` – a class is running (start ≤ now < end): its class timer;
    * `results` – a class ended less than #{30} minutes ago and none is
      running: its WOD's leaderboard;
    * `preview` – the next class of the day: its WOD and bookings;
    * `idle` – nothing left today.

  A running class wins over results, the latest-starting running class over
  an earlier one; cancelled classes are skipped.

  Staff can pin something else (`source: "staff"`, ADR-253): `wod`, `timer`,
  `leaderboard`, `bookings` or `class`, optionally for one class and until
  a time. An override for a class no longer on today's screen falls back to
  automatic.
  """

  @results_minutes 30

  def results_minutes, do: @results_minutes

  @doc """
  `%{source, view, slot_id, until}` for `classes`
  (`%{id, scheduled_at, duration_minutes, cancelled}`) at `now`, honouring
  `override` (`%{view, slot_id, until}` or nil).
  """
  def resolve(classes, override, %DateTime{} = now) do
    case staff(override, classes) do
      nil -> auto(classes, now)
      focus -> focus
    end
  end

  defp staff(nil, _classes), do: nil

  defp staff(%{slot_id: nil} = override, _classes),
    do: %{source: "staff", view: override.view, slot_id: nil, until: override.until}

  defp staff(%{slot_id: slot_id} = override, classes) do
    if Enum.any?(classes, &(&1.id == slot_id)),
      do: %{source: "staff", view: override.view, slot_id: slot_id, until: override.until},
      else: nil
  end

  @doc "The automatic focus alone."
  def auto(classes, %DateTime{} = now) do
    live = classes |> Enum.reject(& &1.cancelled) |> Enum.sort_by(& &1.scheduled_at, DateTime)

    running =
      live
      |> Enum.filter(&(started?(&1, now) and not ended?(&1, now)))
      |> List.last()

    recent =
      live
      |> Enum.filter(&(ended?(&1, now) and within_results?(&1, now)))
      |> List.last()

    next = Enum.find(live, &(not started?(&1, now)))

    cond do
      running -> focus("timer", running)
      recent -> focus("results", recent)
      next -> focus("preview", next)
      true -> %{source: "auto", view: "idle", slot_id: nil, until: nil}
    end
  end

  defp focus(view, class), do: %{source: "auto", view: view, slot_id: class.id, until: nil}

  @doc "When a class ends."
  def ends_at(%{scheduled_at: at, duration_minutes: minutes}),
    do: DateTime.add(at, (minutes || 60) * 60, :second)

  defp started?(class, now), do: DateTime.compare(class.scheduled_at, now) != :gt
  defp ended?(class, now), do: DateTime.compare(ends_at(class), now) != :gt

  defp within_results?(class, now),
    do: DateTime.diff(now, ends_at(class), :second) < @results_minutes * 60
end
