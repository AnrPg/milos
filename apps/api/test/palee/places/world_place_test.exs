defmodule Palee.Places.Domain.WorldPlaceTest do
  use ExUnit.Case, async: true

  alias Palee.Places.Domain.WorldPlace

  @house %{
    label: "Main St 1, Springfield",
    address: "Main St 1",
    neighbourhood: nil,
    city: "Springfield",
    country_code: "US",
    country: "United States",
    latitude: 39.781234,
    longitude: -89.650987,
    layer: "house",
    osm_ref: "N1"
  }

  test "ids are stable, version 5, and differ by slug" do
    id = WorldPlace.id("osm-r1")
    assert id == WorldPlace.id("osm-r1")
    assert id != WorldPlace.id("osm-r2")
    assert <<_::binary-size(14), "5", _::binary>> = id
  end

  test "radius from the bounding box, clamped; else by type" do
    assert WorldPlace.radius(%{extent: [23.70, 38.01, 23.75, 37.99]}) in 2_000..3_000
    assert WorldPlace.radius(%{extent: [0.0, 10.0, 10.0, 0.0]}) == 50_000
    assert WorldPlace.radius(%{extent: [0.0, 0.0001, 0.0001, 0.0]}) == 300
    assert WorldPlace.radius(%{osm_value: "village"}) == 1_500
  end

  test "results that are neither areas nor addresses are dropped" do
    assert WorldPlace.suggestion(%{@house | layer: "country"}) == nil
    assert WorldPlace.suggestion(%{@house | osm_ref: nil}) == nil
  end

  test "an address with no neighbourhood near becomes a coarse grid cell named after its city" do
    address = WorldPlace.suggestion(@house)
    assert address.kind == "address"

    far_area =
      Map.merge(@house, %{
        layer: "district",
        name: "Far",
        osm_ref: "R9",
        latitude: 40.5,
        osm_value: "suburb"
      })

    for local <- [nil, far_area] do
      area = WorldPlace.area_for_address(address, local, nil)
      assert %{kind: "neighbourhood", name: "Springfield", radius_m: 1_500} = area
      assert {area.latitude, area.longitude} == {39.78, -89.65}
      assert area.slug == "geo-39.78--89.65"
      assert area.context == "United States"
    end
  end
end
