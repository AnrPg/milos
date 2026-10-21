defmodule Palee.FakeGeocoder do
  @moduledoc "Test stand-in for Photon: one known address, an outage on «down»."

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

  @impl true
  def search(query, _opts) do
    cond do
      query =~ ~r/down/i -> {:error, :geocoder_unavailable}
      query =~ ~r/Νέγρη|negri/i -> {:ok, [@kypseli]}
      true -> {:ok, []}
    end
  end

  @impl true
  def reverse(latitude, longitude, _opts) when latitude > 37.9 and latitude < 38.1,
    do: {:ok, %{@kypseli | latitude: latitude, longitude: longitude}}

  def reverse(_latitude, _longitude, _opts), do: {:ok, nil}
end
