defmodule Palee.Infrastructure.Places.GeonamesSource do
  @moduledoc """
  Downloads the GeoNames dump (ADR-188): `cities500.zip` (~10 MB, towns of
  500+ people and their sections), `admin1CodesASCII.txt` and
  `countryInfo.txt`. The base URL is configurable so a mirror can be used.
  Data © GeoNames, CC BY 4.0.
  """

  @behaviour Palee.Places.Ports.WorldGazetteerSource

  require Logger

  @default_base_url "https://download.geonames.org/export/dump"

  @impl true
  def fetch do
    with {:ok, zip} <- download("cities500.zip"),
         {:ok, places} <- unzip(zip, ~c"cities500.txt"),
         {:ok, admin1} <- download("admin1CodesASCII.txt"),
         {:ok, countries} <- download("countryInfo.txt") do
      {:ok, %{places: lines(places), admin1: lines(admin1), countries: lines(countries)}}
    end
  end

  defp download(file) do
    case Req.get(base_url() <> "/" <> file,
           headers: [{"user-agent", "Palee/1.0 (+https://palee.com)"}],
           receive_timeout: 120_000,
           decode_body: false,
           retry: :transient
         ) do
      {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %Req.Response{status: status}} ->
        Logger.warning("geonames #{file} answered #{status}")
        {:error, :source_unavailable}

      {:error, reason} ->
        Logger.warning("geonames #{file} failed: #{inspect(reason)}")
        {:error, :source_unavailable}
    end
  end

  defp unzip(zip, name) do
    case :zip.unzip(zip, [:memory, {:file_list, [name]}]) do
      {:ok, [{^name, content}]} -> {:ok, content}
      _other -> {:error, :source_unreadable}
    end
  end

  defp lines(text), do: text |> String.splitter("\n", trim: true)

  defp base_url do
    :palee
    |> Application.get_env(:geonames, [])
    |> Keyword.get(:base_url, @default_base_url)
  end
end
