defmodule Palee.Infrastructure.Facility.PhotonGeocoder do
  @moduledoc """
  Geocoding through Photon (OpenStreetMap data, ADR-141). The base URL is
  configurable so production can point at a self-hosted Photon. Only the
  typed address or the dropped pin is sent, never member data.
  """

  @behaviour Palee.Application.Ports.Geocoder

  require Logger

  # Photon translates names only into these; anything else gets local names.
  @languages ~w(en de fr it)
  @default_base_url "https://photon.komoot.io"

  @impl true
  def search(query, opts) do
    params =
      [q: query, limit: Keyword.get(opts, :limit, 5), lang: language(opts)]
      |> put_near(Keyword.get(opts, :near))
      |> put_layers(Keyword.get(opts, :layers, []))

    with {:ok, features} <- get("/api/", params) do
      {:ok, features |> Enum.map(&to_place/1) |> Enum.reject(&is_nil/1)}
    end
  end

  @impl true
  def reverse(latitude, longitude, opts) do
    params =
      [lat: latitude, lon: longitude, limit: 1, lang: language(opts)]
      |> put_layers(Keyword.get(opts, :layers, ~w(house street)))

    with {:ok, features} <- get("/reverse", params) do
      place = features |> Enum.map(&to_place/1) |> Enum.find(& &1)
      {:ok, place && pinned(place, latitude, longitude, opts)}
    end
  end

  # An address under a dropped pin keeps the pin; a looked-up area keeps its
  # own centre (ADR-188 asks with `layers`).
  defp pinned(place, latitude, longitude, opts) do
    if Keyword.has_key?(opts, :layers),
      do: place,
      else: %{place | latitude: latitude, longitude: longitude}
  end

  defp get(path, params) do
    (base_url() <> path)
    |> Req.get(
      params: params,
      headers: [{"user-agent", "Palee/1.0 (+https://palee.com)"}],
      receive_timeout: 5_000,
      retry: false
    )
    |> case do
      {:ok, %Req.Response{status: 200, body: %{"features" => features}}} when is_list(features) ->
        {:ok, features}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("photon geocoder answered #{status}")
        {:error, :geocoder_unavailable}

      {:error, reason} ->
        Logger.warning("photon geocoder failed: #{inspect(reason)}")
        {:error, :geocoder_unavailable}
    end
  end

  defp to_place(%{"geometry" => %{"coordinates" => [lng, lat]}, "properties" => props})
       when is_number(lng) and is_number(lat) do
    street = join([props["street"], props["housenumber"]], " ")
    address = street || props["name"]
    neighbourhood = props["district"] || props["locality"] || props["suburb"]
    city = props["city"] || props["town"] || props["village"]

    %{
      label:
        join([props["name"] != address && props["name"], address, neighbourhood, city], ", ") ||
          "",
      address: address,
      neighbourhood: neighbourhood,
      city: city,
      country_code: props["countrycode"] && String.upcase(props["countrycode"]),
      latitude: lat * 1.0,
      longitude: lng * 1.0,
      name: props["name"],
      state: props["state"],
      country: props["country"],
      layer: props["type"],
      osm_ref: osm_ref(props["osm_type"], props["osm_id"]),
      osm_value: props["osm_value"],
      extent: extent(props["extent"])
    }
  end

  defp to_place(_feature), do: nil

  defp join(parts, separator) do
    case Enum.filter(parts, &(is_binary(&1) and &1 != "")) do
      [] -> nil
      kept -> Enum.join(Enum.uniq(kept), separator)
    end
  end

  # "R12345": the OSM object, stable across languages and refreshes.
  defp osm_ref(type, id) when type in ~w(N W R) and is_integer(id),
    do: type <> Integer.to_string(id)

  defp osm_ref(_type, _id), do: nil

  defp extent([_, _, _, _] = box) do
    if Enum.all?(box, &is_number/1), do: Enum.map(box, &(&1 * 1.0))
  end

  defp extent(_box), do: nil

  defp put_layers(params, layers), do: params ++ Enum.map(layers, &{:layer, &1})

  defp put_near(params, {lat, lng}), do: params ++ [lat: lat, lon: lng]
  defp put_near(params, _near), do: params

  defp language(opts) do
    case Keyword.get(opts, :language) do
      language when language in @languages -> language
      _other -> "default"
    end
  end

  defp base_url do
    :palee
    |> Application.get_env(:photon, [])
    |> Keyword.get(:base_url, @default_base_url)
  end
end
