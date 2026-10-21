defmodule MilosTraining.Places.Domain.OriginTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Places.Domain.{AlertPolicy, Cursor, Origin, SearchArea, SearchKey}

  @kypseli %{
    id: "a0000000-0000-0000-0000-000000000001",
    name: "Κυψέλη",
    latitude: 38.001,
    longitude: 23.738
  }
  @patisia %{
    id: "a0000000-0000-0000-0000-000000000002",
    name: "Πατήσια",
    latitude: 38.018,
    longitude: 23.733
  }

  describe "requests" do
    test "a device position is rounded to 3 decimals (≈100 m)" do
      assert {:ok, {:point, 38.001, 23.735}} =
               Origin.parse_request(%{
                 "type" => "point",
                 "latitude" => 38.000563,
                 "longitude" => 23.7345526
               })

      assert {:ok, {:point, -33.857, 151.215}} =
               Origin.parse_request(%{type: "point", latitude: -33.85678, longitude: 151.21529})
    end

    test "area, a gazetteer place or a typed place" do
      assert {:ok, nil} = Origin.parse_request(nil)
      assert {:ok, :area} = Origin.parse_request(%{"type" => "area"})

      assert {:ok, {:neighbourhood, "a0000000-0000-0000-0000-000000000001"}} =
               Origin.parse_request(%{
                 "type" => "place",
                 "neighbourhood_id" => String.upcase(@kypseli.id)
               })

      assert {:ok, {:query, "Φωκίωνος Νέγρη"}} =
               Origin.parse_request(%{"type" => "place", "query" => "  Φωκίωνος   Νέγρη "})
    end

    test "rejects what it cannot use" do
      for spec <- [
            %{"type" => "point", "latitude" => 91, "longitude" => 0},
            %{"type" => "point", "latitude" => "38", "longitude" => "23"},
            %{"type" => "place", "neighbourhood_id" => "kypseli"},
            %{"type" => "place", "query" => "x"},
            %{"type" => "home"},
            "area"
          ] do
        assert {:error, [origin: _]} = Origin.parse_request(spec), inspect(spec)
      end
    end
  end

  describe "resolution" do
    defp resolve(overrides) do
      Origin.resolve(
        Map.merge(%{neighbourhoods: [], requested: nil, area: [], home: nil}, overrides)
      )
    end

    test "the filter's neighbourhoods win over everything" do
      device = Origin.from_point("point", {37.9, 23.7}, nil)

      assert {:ok, %{type: "neighbourhoods", label: "Κυψέλη, Πατήσια", points: points}} =
               resolve(%{
                 neighbourhoods: [@kypseli, @patisia],
                 requested: device,
                 area: [@patisia]
               })

      assert points == [{38.001, 23.738}, {38.018, 23.733}]
    end

    test "then what the request names, then the saved area, then the box" do
      device = Origin.from_point("point", {37.9, 23.7}, "Κουκάκι")
      box = Origin.from_point("box", {37.95, 23.72}, "Νέος Κόσμος")

      assert {:ok, %{type: "point", label: "Κουκάκι"}} =
               resolve(%{requested: device, area: [@kypseli], home: box})

      assert {:ok, %{type: "area", neighbourhood_ids: [_]}} =
               resolve(%{requested: :area, area: [@kypseli], home: box})

      assert {:ok, %{type: "area"}} = resolve(%{area: [@kypseli], home: box})
      assert {:ok, %{type: "box"}} = resolve(%{requested: :area, home: box})
      assert {:ok, %{type: "box"}} = resolve(%{home: fn -> box end})
      assert {:error, :origin_required} = resolve(%{home: fn -> nil end})
    end

    test "the box is only looked up when nothing else applies" do
      home = fn -> flunk("the box should not be looked up") end
      assert {:ok, %{type: "area"}} = resolve(%{area: [@kypseli], home: home})
    end

    test "presents its type, label and first point" do
      assert %{type: "area", latitude: 38.001, longitude: 23.738, neighbourhood_ids: [_, _]} =
               Origin.present(Origin.from_places("area", [@kypseli, @patisia]))
    end
  end

  describe "the search area" do
    test "a circle comes with a box that encloses it" do
      area = SearchArea.circle([{38.0, 23.73}], 3_000.0)
      {west, south, east, north} = area.bbox

      for {lat, lng} <- [{38.027, 23.73}, {37.973, 23.73}, {38.0, 23.764}, {38.0, 23.696}] do
        assert SearchArea.distance_m({38.0, 23.73}, {lat, lng}) <= 3_050
        assert lat > south and lat < north and lng > west and lng < east
      end
    end

    test "several origins share one box" do
      area = SearchArea.circle([{38.001, 23.738}, {40.64, 22.944}], 1_000.0)
      {_west, south, _east, north} = area.bbox
      assert south < 38.0 and north > 40.64
    end

    test "a viewport becomes its centre and the radius to its corners" do
      assert {:ok, %{points: [{lat, lng}], radius_m: radius, bbox: {23.7, 37.95, 23.8, 38.05}}} =
               SearchArea.viewport({23.7, 37.95, 23.8, 38.05})

      assert_in_delta lat, 38.0, 1.0e-9
      assert_in_delta lng, 23.75, 1.0e-9
      assert radius > SearchArea.distance_m({38.0, 23.75}, {38.05, 23.8})
      assert {:error, :viewport_too_large} = SearchArea.viewport({23.0, 37.0, 24.0, 38.5})
      assert {:error, :invalid_bbox} = SearchArea.viewport({23.8, 37.95, 23.7, 38.05})
      assert {:error, :invalid_bbox} = SearchArea.viewport({"a", 1, 2, 3})
    end

    test "distances show to one decimal of a kilometre; wider radii come from a ladder" do
      assert SearchArea.distance_km(2_849.0) == 2.8
      assert SearchArea.distance_km(2_851.0) == 2.9
      assert SearchArea.distance_km(nil) == nil
      assert SearchArea.wider_radii_km(3.0) == [10.0, 25.0]
      assert SearchArea.wider_radii_km(10.0) == [25.0, 50.0]
      assert SearchArea.wider_radii_km(50.0) == []
      assert SearchArea.thin?(4)
      refute SearchArea.thin?(5)
    end
  end

  test "cursors round-trip per kind and reject anything else" do
    id = @kypseli.id
    at = ~U[2026-10-24 08:00:00.000000Z]

    assert {:ok, %{at: ^at, id: ^id}} =
             Cursor.decode("events", Cursor.encode("events", %{starts_at: at, id: id}))

    token = Cursor.encode("boxes", %{rank: 0, distance_m: 1234.5678, organization_id: id})
    assert {:ok, %{rank: 0, distance_m: 1234.5678, id: ^id}} = Cursor.decode("boxes", token)
    assert {:error, [cursor: _]} = Cursor.decode("clubs", token)
    assert {:error, [cursor: _]} = Cursor.decode("posts", "not-a-cursor")
    assert {:ok, nil} = Cursor.decode("posts", nil)
  end

  test "gazetteer names match without case or accents" do
    assert SearchKey.normalize("  ΚΥΨΈΛΗ ") == "κυψελη"
    assert SearchKey.normalize("Άνω Πόλη") == "ανω πολη"
    assert SearchKey.normalize("Πειραιάς") == "πειραιασ"
  end

  test "alerts are due once per Athens day" do
    assert AlertPolicy.day(~U[2026-10-21 22:30:00Z]) == ~D[2026-10-22]
    assert AlertPolicy.due?(nil, ~D[2026-10-22])
    assert AlertPolicy.due?(~D[2026-10-21], ~D[2026-10-22])
    refute AlertPolicy.due?(~D[2026-10-22], ~D[2026-10-22])
    refute AlertPolicy.notify?(0)
    assert AlertPolicy.dedupe_key("f", ~D[2026-10-22]) == "around_new_matches:f:2026-10-22"
  end
end
