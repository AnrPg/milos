defmodule MilosTraining.Infrastructure.Facility.PhotonGeocoder do
  @moduledoc """
  Geocoding through Photon (OpenStreetMap data, ADR-141). The base URL is
  configurable so production can point at a self-hosted Photon. Only the
  typed address or the dropped pin is sent, never member data.
  """

  @behaviour MilosTraining.Application.Ports.Geocoder

  require Logger

  # Photon translates names only into these; anything else gets local names.
  @languages ~w(en de fr it)
  @default_base_url "https://photon.komoot.io"

  @impl true
  def search(query, opts) do
    params =
      [q: query, limit: Keyword.get(opts, :limit, 5), lang: language(opts)]
      |> put_near(Keyword.get(opts, :near))

    with {:ok, features} <- get("/api/", params) do
      {:ok, features |> Enum.map(&to_place/1) |> Enum.reject(&is_nil/1)}
    end
  end

  @impl true
  def reverse(latitude, longitude, opts) do
    params = [
      lat: latitude,
      lon: longitude,
      limit: 1,
      lang: language(opts),
      layer: "house",
      layer: "street"
    ]

    with {:ok, features} <- get("/reverse", params) do
      place = features |> Enum.map(&to_place/1) |> Enum.find(& &1)
      {:ok, place && %{place | latitude: latitude, longitude: longitude}}
    end
  end

  defp get(path, params) do
    (base_url() <> path)
    |> Req.get(
      params: params,
      headers: [{"user-agent", "Thumoa/1.0 (+https://thumoa.com)"}],
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
      longitude: lng * 1.0
    }
  end

  defp to_place(_feature), do: nil

  defp join(parts, separator) do
    case Enum.filter(parts, &(is_binary(&1) and &1 != "")) do
      [] -> nil
      kept -> Enum.join(Enum.uniq(kept), separator)
    end
  end

  defp put_near(params, {lat, lng}), do: params ++ [lat: lat, lon: lng]
  defp put_near(params, _near), do: params

  defp language(opts) do
    case Keyword.get(opts, :language) do
      language when language in @languages -> language
      _other -> "default"
    end
  end

  defp base_url do
    :milos_training
    |> Application.get_env(:photon, [])
    |> Keyword.get(:base_url, @default_base_url)
  end
end
