defmodule Palee.Application.WorldGazetteer do
  @moduledoc """
  Keeps every town of 500+ people worldwide in the gazetteer (ADR-188), from
  GeoNames, so area search answers from our own database and the geocoder
  is only needed for addresses and small neighbourhoods. Refreshed when
  missing or older than a month; curated places win over their GeoNames
  twins.
  """

  require Logger

  alias Palee.Places

  @source "geonames"
  @max_age_s 30 * 86_400

  @doc "Imports the towns unless a recent import is there."
  def refresh_if_stale(now \\ DateTime.utc_now()) do
    case Places.reference_refreshed_at(@source) do
      %DateTime{} = at ->
        if DateTime.diff(now, at) < @max_age_s, do: {:ok, :fresh}, else: refresh()

      nil ->
        refresh()
    end
  end

  @doc "Downloads the towns and upserts them; returns how many were written."
  def refresh do
    with {:ok, %{places: lines, admin1: admin1, countries: countries}} <- source().fetch() do
      admin1 = Places.geonames_admin1_names(admin1)
      countries = Places.geonames_country_names(countries)
      curated = Places.reference_places("curated")

      count =
        lines
        |> Stream.map(&Places.geonames_place(&1, admin1, countries))
        |> Stream.reject(&(is_nil(&1) or Places.duplicates_known_place?(&1, curated)))
        |> then(&Places.upsert_reference_places(@source, &1))

      Logger.info("world gazetteer: #{count} GeoNames places imported")
      {:ok, %{imported: count}}
    end
  end

  defp source, do: Application.fetch_env!(:palee, :world_gazetteer_source)
end
