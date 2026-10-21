defmodule Palee.Places.Domain.SearchArea do
  @moduledoc """
  Where a Γύρω μου search looks (ADR-154), as numbers the database can
  index: one or more origin points with a radius, always together with the
  bounding box that encloses them. A map viewport («Ψάξε εδώ») becomes the
  same shape: its centre with the radius of the circle around it, plus the
  viewport itself. Both predicates reach the GiST indexes.

  Also: rounding a device position to 3 decimals (≈100 m; it is never
  stored), rounding distances for display, and the wider radii offered when
  a search finds little.
  """

  @earth_radius_m 6_371_008.8
  @metres_per_degree 111_320.0
  @max_viewport_m 60_000.0
  @wider_ladder_km [10.0, 25.0, 50.0]
  @thin_below 5

  @type point :: {float(), float()}
  @type bbox :: {float(), float(), float(), float()}
  @type t :: %{points: [point()], radius_m: float(), bbox: bbox()}

  @doc "A device or one-off position, at most 3 decimals (≈100 m)."
  def round_point(latitude, longitude)
      when is_number(latitude) and is_number(longitude) and latitude >= -90 and latitude <= 90 and
             longitude >= -180 and longitude <= 180,
      do: {:ok, {Float.round(latitude * 1.0, 3), Float.round(longitude * 1.0, 3)}}

  def round_point(_latitude, _longitude), do: {:error, :invalid_point}

  @doc "A circle (or several, one per origin point) of `radius_m`."
  def circle(points, radius_m) when points != [] and radius_m > 0 do
    %{points: points, radius_m: radius_m * 1.0, bbox: enclosing_bbox(points, radius_m)}
  end

  @doc """
  A map viewport `{west, south, east, north}` (no antimeridian crossing, at
  most #{trunc(@max_viewport_m / 1000)} km corner to corner): its centre,
  the radius reaching its corners, and the box itself.
  """
  def viewport({west, south, east, north})
      when is_number(west) and is_number(south) and is_number(east) and is_number(north) do
    cond do
      not (south >= -90 and north <= 90 and west >= -180 and east <= 180) ->
        {:error, :invalid_bbox}

      west >= east or south >= north ->
        {:error, :invalid_bbox}

      distance_m({south, west}, {north, east}) > @max_viewport_m ->
        {:error, :viewport_too_large}

      true ->
        center = {(south + north) / 2, (west + east) / 2}

        radius =
          [{south, west}, {south, east}, {north, west}, {north, east}]
          |> Enum.map(&distance_m(center, &1))
          |> Enum.max()

        {:ok,
         %{
           points: [center],
           radius_m: Float.ceil(radius + 1.0),
           bbox: {west * 1.0, south * 1.0, east * 1.0, north * 1.0}
         }}
    end
  end

  def viewport(_bbox), do: {:error, :invalid_bbox}

  @doc "The same origin points with another radius (wider counts)."
  def widen(%{points: points}, radius_m), do: circle(points, radius_m)

  @doc "Great-circle distance in metres."
  def distance_m({lat1, lng1}, {lat2, lng2}) do
    phi1 = radians(lat1)
    phi2 = radians(lat2)
    d_phi = radians(lat2 - lat1)
    d_lambda = radians(lng2 - lng1)

    a =
      :math.sin(d_phi / 2) ** 2 +
        :math.cos(phi1) * :math.cos(phi2) * :math.sin(d_lambda / 2) ** 2

    2 * @earth_radius_m * :math.atan2(:math.sqrt(a), :math.sqrt(1 - a))
  end

  @doc "Distance shown on a card: kilometres to one decimal."
  def distance_km(nil), do: nil
  def distance_km(metres) when is_number(metres), do: Float.round(metres / 1000, 1)

  @doc "Up to two radii wider than `radius_km`, from 10, 25, 50 km."
  def wider_radii_km(radius_km),
    do: @wider_ladder_km |> Enum.filter(&(&1 > radius_km)) |> Enum.take(2)

  @doc "A search is thin when every section together found fewer than #{@thin_below}."
  def thin?(total) when is_integer(total), do: total < @thin_below

  # The box around each circle, joined, with a 2% margin so it always
  # contains the spheroid circle PostGIS measures. Longitude degrees shrink
  # with latitude; near the poles the box opens to every longitude.
  defp enclosing_bbox(points, radius_m) do
    radius_m = radius_m * 1.02

    points
    |> Enum.map(fn {lat, lng} ->
      d_lat = radius_m / @metres_per_degree
      cos = :math.cos(radians(lat))

      d_lng =
        if cos < 0.01, do: 180.0, else: radius_m / (@metres_per_degree * cos)

      {max(lng - d_lng, -180.0), max(lat - d_lat, -90.0), min(lng + d_lng, 180.0),
       min(lat + d_lat, 90.0)}
    end)
    |> Enum.reduce(fn {w, s, e, n}, {w2, s2, e2, n2} ->
      {min(w, w2), min(s, s2), max(e, e2), max(n, n2)}
    end)
    |> then(fn {w, s, e, n} -> {w * 1.0, s * 1.0, e * 1.0, n * 1.0} end)
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
