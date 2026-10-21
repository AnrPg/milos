defmodule Palee.Application.ListBookablePlaces do
  @moduledoc """
  Phase 2 location picker (Πρόγραμμα ▾): every location whose schedule the
  user can book, across all gyms they are an active member of, nearest
  first.

  Distance is measured from `near` (the device's position, when the user
  allows it), otherwise from the user's home location in their first gym that
  has one, so the list still reads "nearest to where you train". Places without
  coordinates sort last, by name. Other gyms' locations are never listed here.
  """

  alias Palee.{Facility, Organizations}

  def call(user_id, near \\ nil) when is_binary(user_id) do
    memberships = Organizations.list_memberships(user_id)

    places =
      Enum.flat_map(memberships, fn %{membership: membership, organization: organization} ->
        %{organization_id: organization.id, user_id: user_id}
        |> Facility.list_locations()
        |> Enum.map(&place(&1, organization, membership.home_location_id))
      end)

    origin = near || home_point(places)

    places
    |> Enum.map(&Map.put(&1, :distance_km, distance(origin, &1)))
    |> Enum.sort_by(&sort_key/1)
  end

  defp place(location, organization, home_location_id) do
    %{
      id: location.id,
      name: location.name,
      address: location.address,
      neighbourhood: location.neighbourhood,
      city: location.city,
      latitude: location.latitude,
      longitude: location.longitude,
      home: location.id == home_location_id,
      organization: %{id: organization.id, slug: organization.slug, name: organization.name}
    }
  end

  defp home_point(places) do
    case Enum.find(places, &(&1.home and is_number(&1.latitude))) do
      nil -> nil
      home -> {home.latitude, home.longitude}
    end
  end

  defp distance(nil, _place), do: nil

  defp distance(origin, place) do
    case Facility.distance_km(origin, {place.latitude, place.longitude}) do
      nil -> nil
      km -> Float.round(km, 2)
    end
  end

  defp sort_key(%{distance_km: nil} = place), do: {1, 0, not place.home, place.name}
  defp sort_key(place), do: {0, place.distance_km, not place.home, place.name}
end
