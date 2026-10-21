defmodule Palee.Facility.Domain.ResolveScan do
  @moduledoc """
  What a scan at the door means (ADR-155, decision 2; vision §7.5), as one
  pure decision over facts the caller gathered:

  1. A booking at this location whose class starts within the owner's window
     (default 30′ before to 15′ after) → check in to it. Several → the person
     picks (`{:choose, bookings}`). A booking already checked in makes the
     scan a no-op (`{:already_checked_in, ...}`), so scanning twice never
     checks in twice.
  2. Otherwise a member → open gym, when the package covers it or the owner
     doesn't require it; already in open gym today → no-op.
  3. Otherwise a member → nothing to check in to: the classes starting soon
     at this location with spots («Κλείσε θέση») and their next booking.
  4. Otherwise (not a member, no booking) → `:visitor`, the door offers a
     trial.

  A scan of the printed poster (`source: :poster`, board 10 Q1 extra) is
  weaker proof - the code never changes - so it only does step 1: with no
  booking in the window it is `{:poster_no_booking, :member | :visitor}`,
  never open gym, suggestions or a trial offer. An NFC door tag (`:nfc`)
  and the geofenced reminder (`:geofence`) are static proof too (ADR-173)
  and follow the same rule.

  Facts:

    * `bookings`: the person's approved bookings around now, each
      `%{id, starts_at, location_id, attendance}` (`attendance` is the
      recorded status or nil), plus anything the caller wants back;
    * `location_id`: where the door is;
    * `member?`: an active member of the box;
    * `open_gym`: `%{existing: check_in | nil, covered?: boolean}`;
    * `classes`: upcoming classes `%{id, starts_at, location_id, spots_remaining}`;
    * `source`: `:door` (default, the rotating code), `:poster`, `:nfc` or
      `:geofence`.
  """

  alias Palee.Facility.Domain.CheckInRules

  @suggestion_hours 3
  @next_booking_hours 12

  @type decision ::
          {:check_in_class, map()}
          | {:choose, [map()]}
          | {:already_checked_in, {:class, map()} | {:open_gym, map()}}
          | :open_gym
          | {:nothing, %{classes: [map()], next_booking: map() | nil}}
          | :visitor
          | {:poster_no_booking, :member | :visitor}
          | {:error, :booking_not_in_window}

  @doc "The decision for a scan, optionally for a booking the person picked."
  @spec decide(map(), map(), DateTime.t(), binary() | nil) :: decision()
  def decide(facts, settings, %DateTime{} = now, chosen_booking_id \\ nil) do
    candidates = candidates(facts, settings, now)

    case chosen_booking_id do
      nil -> decide_open(facts, settings, now, candidates)
      id -> decide_chosen(candidates, id)
    end
  end

  @doc "Bookings at this location whose window contains `now`, soonest first."
  def candidates(facts, settings, now) do
    facts
    |> Map.get(:bookings, [])
    |> Enum.filter(&here?(&1, facts.location_id))
    |> Enum.filter(&CheckInRules.in_window?(settings, &1.starts_at, now))
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end

  defp decide_chosen(candidates, id) do
    case Enum.find(candidates, &(&1.id == id)) do
      nil -> {:error, :booking_not_in_window}
      %{attendance: "attended"} = booking -> {:already_checked_in, {:class, booking}}
      %{attendance: nil} = booking -> {:check_in_class, booking}
      _recorded -> {:error, :booking_not_in_window}
    end
  end

  defp decide_open(facts, settings, now, candidates) do
    attended = Enum.filter(candidates, &(&1.attendance == "attended"))
    open = Enum.filter(candidates, &is_nil(&1.attendance))

    cond do
      attended != [] ->
        {:already_checked_in, {:class, hd(attended)}}

      length(open) == 1 ->
        {:check_in_class, hd(open)}

      open != [] ->
        {:choose, open}

      static_source?(facts[:source]) ->
        {:poster_no_booking, if(facts[:member?], do: :member, else: :visitor)}

      facts[:member?] == true ->
        member_without_booking(facts, settings, now)

      true ->
        :visitor
    end
  end

  @static_sources [:poster, :nfc, :geofence]

  @doc "Whether a source is static proof that only checks in a booking (ADR-155 §5, ADR-173)."
  def static_source?(source), do: source in @static_sources

  defp member_without_booking(facts, settings, now) do
    open_gym = Map.get(facts, :open_gym, %{})
    settings = CheckInRules.effective(settings)

    cond do
      open_gym[:existing] != nil ->
        {:already_checked_in, {:open_gym, open_gym.existing}}

      open_gym[:covered?] == true or not settings.open_gym_requires_package ->
        :open_gym

      true ->
        {:nothing, %{classes: suggestions(facts, now), next_booking: next_booking(facts, now)}}
    end
  end

  @doc "Classes at this location starting in the next #{@suggestion_hours} hours with a spot."
  def suggestions(facts, now) do
    until = DateTime.add(now, @suggestion_hours * 3600, :second)
    booked = facts |> Map.get(:bookings, []) |> MapSet.new(&Map.get(&1, :scheduled_class_id))

    facts
    |> Map.get(:classes, [])
    |> Enum.filter(fn class ->
      here?(class, facts.location_id) and (class.spots_remaining || 0) > 0 and
        DateTime.compare(class.starts_at, now) != :lt and
        DateTime.compare(class.starts_at, until) != :gt and
        not MapSet.member?(booked, class.id)
    end)
    |> Enum.sort_by(& &1.starts_at, DateTime)
  end

  defp next_booking(facts, now) do
    until = DateTime.add(now, @next_booking_hours * 3600, :second)

    facts
    |> Map.get(:bookings, [])
    |> Enum.filter(fn booking ->
      DateTime.compare(booking.starts_at, now) == :gt and
        DateTime.compare(booking.starts_at, until) != :gt
    end)
    |> Enum.min_by(& &1.starts_at, DateTime, fn -> nil end)
  end

  # A class without a location belongs to every location of the box.
  defp here?(%{location_id: nil}, _location_id), do: true
  defp here?(%{location_id: location_id}, location_id), do: true
  defp here?(_item, _location_id), do: false
end
