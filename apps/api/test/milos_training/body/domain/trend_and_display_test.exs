defmodule MilosTraining.Body.Domain.TrendAndDisplayTest do
  use ExUnit.Case, async: true

  alias MilosTraining.Body.Domain.{DisplayPolicy, TrendPolicy}

  defp points(values) do
    values
    |> Enum.with_index()
    |> Enum.map(fn {value, i} ->
      %{at: DateTime.add(~U[2026-07-01 08:00:00Z], i * 7 * 86_400), value: value}
    end)
  end

  describe "trend words" do
    test "classify relative change into five neutral words" do
      assert TrendPolicy.classify(100, 100.3) == "steady"
      assert TrendPolicy.classify(100, 99.0) == "slightly_down"
      assert TrendPolicy.classify(100, 97.0) == "down"
      assert TrendPolicy.classify(100, 101.0) == "slightly_up"
      assert TrendPolicy.classify(100, 103.0) == "up"
      assert TrendPolicy.classify(0, 1) == nil
    end

    test "one noisy reading does not flip the smoothed word" do
      # Steady around 74 kg, then one heavy day.
      assert TrendPolicy.word(points([74.0, 74.1, 73.9, 74.0, 76.0])) == "slightly_up"
      assert TrendPolicy.word(points([74.0, 74.1, 73.9, 74.0, 74.2])) == "steady"
      assert TrendPolicy.word(points([75.0, 74.2, 73.4, 72.6, 71.8, 71.0])) == "down"
      assert TrendPolicy.word(points([74.0])) == nil
      assert TrendPolicy.word([]) == nil
    end

    test "smoothing orders points oldest first" do
      [first, second] = TrendPolicy.smooth(Enum.reverse(points([70.0, 80.0])))
      assert first.smoothed == 70.0
      assert second.smoothed == 73.0
    end

    test "shape: the smoothed series normalized to 0..1, oldest first" do
      shape = TrendPolicy.shape(Enum.reverse(points([80.0, 70.0, 75.0])))
      # Smoothed: 80.0, 77.0, 76.4 -> normalized over 76.4..80.0.
      assert Enum.map(shape, & &1.y) == [1.0, 0.167, 0.0]
      assert Enum.map(shape, & &1.at) == Enum.map(points([0, 0, 0]), & &1.at)
      assert Enum.all?(shape, &(Map.keys(&1) |> Enum.sort() == [:at, :y]))
    end

    test "shape: a flat series is 0.5 throughout; no points, no shape" do
      assert Enum.map(TrendPolicy.shape(points([72.0, 72.0, 72.0])), & &1.y) == [0.5, 0.5, 0.5]
      assert Enum.map(TrendPolicy.shape(points([72.0])), & &1.y) == [0.5]
      assert TrendPolicy.shape([]) == []
    end

    test "ranges" do
      now = ~U[2026-10-20 00:00:00Z]
      assert {:ok, ~U[2026-09-20 00:00:00Z]} = TrendPolicy.since("1m", now)
      assert {:ok, nil} = TrendPolicy.since("all", now)
      assert {:error, :invalid_range} = TrendPolicy.since("2w", now)
    end
  end

  describe "display privacy" do
    @metrics %{"weight" => 72.4, "body_fat" => 22.0, "waist" => 81.0}

    test "number shows every value in the person's units" do
      assert %{metrics: %{"weight" => 72.4, "body_fat" => 22.0, "waist" => 81.0}, withheld: []} =
               DisplayPolicy.metrics(@metrics, %{weight_display: "number", units: "metric"})

      assert %{metrics: %{"weight" => 159.6, "waist" => 31.9}} =
               DisplayPolicy.metrics(@metrics, %{weight_display: "number", units: "imperial"})
    end

    test "trend never returns weight or body fat numbers, only that they exist" do
      shown = DisplayPolicy.metrics(@metrics, %{weight_display: "trend", units: "metric"})
      assert shown.metrics == %{"waist" => 81.0}
      assert shown.withheld == ["body_fat", "weight"]
    end

    test "hidden returns neither the numbers nor that they exist" do
      assert %{metrics: %{"waist" => 81.0}, withheld: []} =
               DisplayPolicy.metrics(@metrics, %{weight_display: "hidden", units: "metric"})
    end

    test "series: numbers, only the trend word, or nothing" do
      series = points([74.5, 73.7, 72.9, 72.1, 71.3, 70.5])
      settings = %{weight_display: "number", units: "metric"}

      assert %{display: "number", trend: "down", points: [%{value: 74.5, smoothed: 74.5} | _]} =
               DisplayPolicy.series("weight", series, settings)

      assert %{display: "trend", trend: "down", points: [], shape: shape} =
               DisplayPolicy.series("weight", series, %{settings | weight_display: "trend"})

      # Under trend: a 0..1 shape, never a value in kg.
      assert length(shape) == 6
      assert hd(shape).y == 1.0 and List.last(shape).y == 0.0
      assert Enum.all?(shape, &(&1.y >= 0 and &1.y <= 1))

      hidden = DisplayPolicy.series("body_fat", series, %{settings | weight_display: "hidden"})
      assert %{display: "hidden", trend: nil, points: []} = hidden
      refute Map.has_key?(hidden, :shape)
      refute Map.has_key?(DisplayPolicy.series("weight", series, settings), :shape)

      # Circumferences always show as numbers.
      assert %{display: "number", points: [_ | _]} =
               DisplayPolicy.series("waist", series, %{settings | weight_display: "hidden"})
    end

    test "deltas respect the display choice" do
      from = %{"weight" => 74.0, "waist" => 83.0, "body_fat" => 23.0}
      to = %{"weight" => 72.4, "waist" => 81.0}

      assert [
               %{metric: "weight", delta: -1.6, direction: "down"},
               %{metric: "waist", delta: -2.0, direction: "down"}
             ] = DisplayPolicy.deltas(from, to, %{weight_display: "number", units: "metric"})

      assert [%{metric: "weight", delta: nil, direction: "down"}, %{metric: "waist"}] =
               DisplayPolicy.deltas(from, to, %{weight_display: "trend", units: "metric"})

      assert [%{metric: "waist"}] =
               DisplayPolicy.deltas(from, to, %{weight_display: "hidden", units: "metric"})
    end
  end
end
