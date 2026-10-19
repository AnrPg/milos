defmodule MilosTraining.Facility.Domain.GeoDistance do
  @moduledoc "Great-circle distance between two coordinates (haversine), in kilometres."

  @earth_radius_km 6371.0

  def km({lat1, lng1}, {lat2, lng2})
      when is_number(lat1) and is_number(lng1) and is_number(lat2) and is_number(lng2) do
    d_lat = radians(lat2 - lat1)
    d_lng = radians(lng2 - lng1)

    a =
      :math.pow(:math.sin(d_lat / 2), 2) +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) * :math.pow(:math.sin(d_lng / 2), 2)

    2 * @earth_radius_km * :math.asin(:math.sqrt(min(a, 1.0)))
  end

  def km(_from, _to), do: nil

  defp radians(degrees), do: degrees * :math.pi() / 180
end
