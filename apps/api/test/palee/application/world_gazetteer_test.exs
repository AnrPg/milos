defmodule Palee.Application.WorldGazetteerTest do
  @moduledoc """
  ADR-188: towns worldwide come from GeoNames; curated places win over their
  twins; search is typo-tolerant and ranks namesakes by size.
  """

  use Palee.DataCase, async: false

  alias Palee.Application.{AroundArea, WorldGazetteer}
  alias Palee.Places

  test "imports towns once a month, skipping curated twins and abandoned places" do
    assert {:ok, %{imported: 4}} = WorldGazetteer.refresh_if_stale()
    assert {:ok, :fresh} = WorldGazetteer.refresh_if_stale()

    assert {:ok, %{imported: 4}} =
             WorldGazetteer.refresh_if_stale(DateTime.add(DateTime.utc_now(), 31, :day))

    slugs = "geonames" |> Places.reference_places() |> Enum.map(& &1.slug) |> Enum.sort()
    assert slugs == ~w(gn-2867714 gn-4180386 gn-4505542 gn-6545310)

    [munich] = Places.search_neighbourhoods("munich", 5)

    assert %{name: "Μόναχο", name_en: "Munich", context_en: "Bavaria, Germany", kind: "city"} =
             munich

    assert [%{kind: "neighbourhood"}] = Places.search_neighbourhoods("kreuzberg", 5)
  end

  test "namesakes rank by size, and typos still find the town" do
    {:ok, _result} = WorldGazetteer.refresh()

    assert [%{slug: "athens"}, %{slug: "gn-4180386"}, %{slug: "gn-4505542"} | _rest] =
             Places.search_neighbourhoods("athens", 10)

    assert [%{name_en: "Munich"} | _rest] = Places.search_neighbourhoods("munchen", 5)
    assert [%{name_en: "Munich"} | _rest] = Places.search_neighbourhoods("munih", 5)
  end

  test "an outage leaves the gazetteer as it was" do
    Process.put(:world_gazetteer_source, :down)
    assert {:error, :source_unavailable} = WorldGazetteer.refresh()
    assert Places.reference_places("geonames") == []
  end

  test "imported towns are not repeated from the geocoder; addresses always reach it" do
    {:ok, _result} = WorldGazetteer.refresh()

    # The geocoder's München is the stored town: listed once.
    assert {:ok, %{neighbourhoods: [%{name_en: "Munich"}]}} = AroundArea.neighbourhoods("München")

    assert {:ok, %{remote: "ok", neighbourhoods: suggestions}} =
             AroundArea.neighbourhoods("Oranienstraße 10")

    assert Enum.any?(suggestions, &(&1.kind == "address"))
  end
end
