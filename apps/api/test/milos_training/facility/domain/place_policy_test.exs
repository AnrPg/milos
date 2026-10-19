defmodule MilosTraining.Facility.Domain.PlacePolicyTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Facility.Domain.PlacePolicy

  describe "normalize_opening_hours/1" do
    test "sorts spans and accepts atom keys" do
      assert {:ok,
              [
                %{"weekday" => 1, "opens" => "07:00", "closes" => "12:00"},
                %{"weekday" => 1, "opens" => "16:00", "closes" => "22:00"},
                %{"weekday" => 6, "opens" => "09:00", "closes" => "13:00"}
              ]} =
               PlacePolicy.normalize_opening_hours([
                 %{weekday: 6, opens: "09:00", closes: "13:00"},
                 %{"weekday" => 1, "opens" => "16:00", "closes" => "22:00"},
                 %{"weekday" => 1, "opens" => "07:00", "closes" => "12:00"}
               ])
    end

    test "allows a span that crosses midnight as the day's last span" do
      assert {:ok, [_]} =
               PlacePolicy.normalize_opening_hours([
                 %{"weekday" => 5, "opens" => "18:00", "closes" => "02:00"}
               ])
    end

    test "rejects overlapping spans on one day" do
      assert {:error, :overlapping_spans} =
               PlacePolicy.normalize_opening_hours([
                 %{"weekday" => 2, "opens" => "07:00", "closes" => "12:00"},
                 %{"weekday" => 2, "opens" => "11:00", "closes" => "14:00"}
               ])

      assert {:error, :overlapping_spans} =
               PlacePolicy.normalize_opening_hours([
                 %{"weekday" => 2, "opens" => "07:00", "closes" => "01:00"},
                 %{"weekday" => 2, "opens" => "20:00", "closes" => "22:00"}
               ])
    end

    test "rejects malformed spans" do
      for span <- [
            %{"weekday" => 0, "opens" => "07:00", "closes" => "12:00"},
            %{"weekday" => 8, "opens" => "07:00", "closes" => "12:00"},
            %{"weekday" => 1, "opens" => "7:00", "closes" => "12:00"},
            %{"weekday" => 1, "opens" => "24:00", "closes" => "12:00"},
            %{"weekday" => 1, "opens" => "12:00", "closes" => "12:00"},
            "monday"
          ] do
        assert {:error, :invalid_opening_hours} = PlacePolicy.normalize_opening_hours([span])
      end

      assert {:error, :invalid_opening_hours} = PlacePolicy.normalize_opening_hours(%{})
    end
  end

  test "names collapse whitespace and blank becomes nil" do
    assert PlacePolicy.normalize_name("  Άνω   Πατήσια ") == "Άνω Πατήσια"
    assert PlacePolicy.normalize_name("   ") == nil
    assert PlacePolicy.normalize_country_code(" gr ") == "GR"
    assert PlacePolicy.valid_country_code?("GR")
    refute PlacePolicy.valid_country_code?("GRC")
  end

  test "coordinates keep six decimals" do
    assert PlacePolicy.round_coordinate(37.98381234567) == 37.983812
    assert PlacePolicy.round_coordinate(24) == 24.0
  end
end
