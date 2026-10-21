defmodule Palee.Facility.Domain.GeofencePlan do
  @moduledoc """
  Where the store app reminds a member to check in (ADR-173): the box's
  locations that have a point on the map (ADR-141) and a booking of the
  member whose check-in window has not closed yet. Each region carries those
  windows, so the phone only reminds while one is open; it never asks the
  server where the member is.

  A class without a location belongs to every location of the box. The
  radius is fixed (#{150} m): wide enough for the phone's region monitoring,
  narrow enough to mean "at the door". Pure: callers pass the time.
  """

  alias Palee.Facility.Domain.CheckInRules

  @radius_m 150

  def radius_m, do: @radius_m

  @doc """
  Regions for one box: `locations` (`%{id, name, latitude, longitude,
  archived_at}`), the member's `bookings` (`%{id, starts_at, location_id,
  name, attendance}`) and the box's check-in `rules`.
  """
  def regions(locations, bookings, rules, %DateTime{} = now) do
    places = Enum.filter(locations, &placed?/1)
    open = bookings |> Enum.filter(&is_nil(Map.get(&1, :attendance))) |> windows(rules, now)

    places
    |> Enum.map(fn location ->
      %{
        location: location,
        windows: Enum.filter(open, &(&1.location_id in [nil, location.id]))
      }
    end)
    |> Enum.reject(&(&1.windows == []))
    |> Enum.map(fn %{location: location, windows: windows} ->
      %{
        location_id: location.id,
        location_name: Map.get(location, :name),
        latitude: location.latitude,
        longitude: location.longitude,
        radius_m: @radius_m,
        windows: Enum.map(windows, &Map.delete(&1, :location_id))
      }
    end)
  end

  @doc "Keeps the `limit` regions whose first window opens soonest (phones cap regions)."
  def soonest(regions, limit) do
    regions
    |> Enum.sort_by(&(&1.windows |> hd() |> Map.fetch!(:opens_at)), DateTime)
    |> Enum.take(limit)
  end

  defp windows(bookings, rules, now) do
    bookings
    |> Enum.map(fn booking ->
      {opens_at, closes_at} = CheckInRules.booking_window(rules, booking.starts_at)

      %{
        booking_id: booking.id,
        class_name: Map.get(booking, :name),
        starts_at: booking.starts_at,
        opens_at: opens_at,
        closes_at: closes_at,
        location_id: Map.get(booking, :location_id)
      }
    end)
    |> Enum.filter(&(DateTime.compare(&1.closes_at, now) != :lt))
    |> Enum.sort_by(& &1.opens_at, DateTime)
  end

  defp placed?(location) do
    is_nil(Map.get(location, :archived_at)) and is_number(Map.get(location, :latitude)) and
      is_number(Map.get(location, :longitude))
  end
end
