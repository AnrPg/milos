defmodule Palee.FakeGeocoder do
  @moduledoc """
  Test stand-in for Photon: one known address, an outage on «down», and for
  worldwide area search (ADR-188, `layers` given) Munich, Kreuzberg and an
  address in Kreuzberg, with English names on `language: "en"`.
  """

  @behaviour Palee.Application.Ports.Geocoder

  @kypseli %{
    label: "Φωκίωνος Νέγρη 12, Κυψέλη, Αθήνα",
    address: "Φωκίωνος Νέγρη 12",
    neighbourhood: "Κυψέλη",
    city: "Αθήνα",
    country_code: "GR",
    latitude: 38.000563,
    longitude: 23.7345526
  }

  @munich %{
    label: "München",
    address: "München",
    neighbourhood: nil,
    city: nil,
    country_code: "DE",
    latitude: 48.1371,
    longitude: 11.5754,
    name: "München",
    state: "Bayern",
    country: "Deutschland",
    layer: "city",
    osm_ref: "R62428",
    osm_value: "city",
    extent: [11.3608, 48.2482, 11.7229, 48.0616]
  }

  @kreuzberg %{
    label: "Kreuzberg, Berlin",
    address: "Kreuzberg",
    neighbourhood: nil,
    city: "Berlin",
    country_code: "DE",
    latitude: 52.4986,
    longitude: 13.4033,
    name: "Kreuzberg",
    state: "Berlin",
    country: "Deutschland",
    layer: "district",
    osm_ref: "R55764",
    osm_value: "suburb",
    extent: nil
  }

  @oranien %{
    label: "Oranienstraße 10, Kreuzberg, Berlin",
    address: "Oranienstraße 10",
    neighbourhood: "Kreuzberg",
    city: "Berlin",
    country_code: "DE",
    latitude: 52.50123,
    longitude: 13.41987,
    name: nil,
    state: "Berlin",
    country: "Deutschland",
    layer: "house",
    osm_ref: "N111",
    osm_value: "house",
    extent: nil
  }

  @impl true
  def search(query, opts) do
    if Keyword.has_key?(opts, :layers), do: search_areas(query, opts), else: search_address(query)
  end

  defp search_areas(query, opts) do
    english? = Keyword.get(opts, :language) == "en"

    cond do
      query =~ ~r/halfdown/i ->
        if(english?, do: {:error, :geocoder_unavailable}, else: {:ok, [@munich]})

      query =~ ~r/down/i ->
        {:error, :geocoder_unavailable}

      query =~ ~r/münch|munich/i ->
        {:ok, [english(@munich, english?)]}

      query =~ ~r/kreuz/i ->
        {:ok, [english(@kreuzberg, english?)]}

      query =~ ~r/oranien/i ->
        {:ok, [english(@oranien, english?)]}

      query =~ ~r/kyps|κυψ/i ->
        {:ok,
         [
           %{
             @kreuzberg
             | name: "Κυψέλη",
               latitude: 38.0035,
               longitude: 23.7394,
               osm_ref: "R999",
               country_code: "GR"
           }
         ]}

      true ->
        {:ok, []}
    end
  end

  defp english(place, false), do: place

  defp english(place, true),
    do: %{
      place
      | name: place.name && String.replace(place.name, "München", "Munich"),
        country: "Germany",
        state: place.state && String.replace(place.state, "Bayern", "Bavaria")
    }

  defp search_address(query) do
    cond do
      query =~ ~r/down/i -> {:error, :geocoder_unavailable}
      query =~ ~r/Νέγρη|negri/i -> {:ok, [@kypseli]}
      true -> {:ok, []}
    end
  end

  @impl true
  def reverse(latitude, longitude, opts) do
    if Keyword.has_key?(opts, :layers),
      do: reverse_area(latitude, longitude, opts),
      else: reverse_address(latitude, longitude)
  end

  # Berlin has Kreuzberg; the sea off Athens has no neighbourhood; 0,0 is down.
  defp reverse_area(latitude, _longitude, opts) when latitude > 52.4 and latitude < 52.6,
    do: {:ok, english(@kreuzberg, Keyword.get(opts, :language) == "en")}

  defp reverse_area(latitude, _longitude, _opts) when latitude == 0.0,
    do: {:error, :geocoder_unavailable}

  defp reverse_area(_latitude, _longitude, _opts), do: {:ok, nil}

  defp reverse_address(latitude, longitude) when latitude > 37.9 and latitude < 38.1,
    do: {:ok, %{@kypseli | latitude: latitude, longitude: longitude}}

  defp reverse_address(_latitude, _longitude), do: {:ok, nil}
end
