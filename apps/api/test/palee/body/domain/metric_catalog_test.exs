defmodule Palee.Body.Domain.MetricCatalogTest do
  use ExUnit.Case, async: true

  alias Palee.Body.Domain.MetricCatalog

  test "stores SI values and shows imperial ones back as typed" do
    assert {:ok, %{"weight" => kg, "waist" => cm, "body_fat" => 22.0}} =
             MetricCatalog.validate(
               %{"weight" => 160, "waist" => 32.5, "body_fat" => 22},
               "imperial"
             )

    assert_in_delta kg, 72.575, 0.001
    assert_in_delta cm, 82.55, 0.001
    assert MetricCatalog.present("weight", kg, "imperial") == 160.0
    assert MetricCatalog.present("waist", cm, "imperial") == 32.5
    assert MetricCatalog.present("weight", kg, "metric") == 72.6
    assert MetricCatalog.unit("weight", "imperial") == "lb"
    assert MetricCatalog.unit("thigh_left", "metric") == "cm"
    assert MetricCatalog.unit("body_fat", "imperial") == "%"
  end

  test "accepts numbers typed with a decimal comma and keeps nil as a removal" do
    assert {:ok, %{"weight" => 72.4, "hips" => nil}} =
             MetricCatalog.validate(%{weight: "72,4", hips: nil}, "metric")

    assert MetricCatalog.merge(%{"weight" => 70.0, "hips" => 96.0}, %{
             "weight" => 72.4,
             "hips" => nil
           }) ==
             %{"weight" => 72.4}
  end

  test "rejects unknown metrics, non-numbers and values out of range (range in your units)" do
    assert {:error, :invalid_metric, %{metric: "shoe", reason: "unknown"}} =
             MetricCatalog.validate(%{"shoe" => 42}, "metric")

    assert {:error, :invalid_metric, %{metric: "weight", reason: "not_a_number"}} =
             MetricCatalog.validate(%{"weight" => "heavy"}, "metric")

    assert {:error, :invalid_metric, %{metric: "weight", reason: "out_of_range", unit: "kg"}} =
             MetricCatalog.validate(%{"weight" => 7240}, "metric")

    assert {:error, :invalid_metric, %{reason: "out_of_range", unit: "in", max: max}} =
             MetricCatalog.validate(%{"neck" => 40}, "imperial")

    assert max == 27.6
    assert {:error, :invalid_metric, _} = MetricCatalog.validate(%{"weight" => 72}, "stone")
  end

  test "the catalog lists every metric with its unit and range" do
    catalog = MetricCatalog.catalog("metric")
    assert length(catalog) == 13
    assert %{key: "weight", unit: "kg", min: 20.0, max: 400.0, sensitive: true} = hd(catalog)
    assert Enum.find(catalog, &(&1.key == "waist")).sensitive == false
  end

  test "clean drops unknown keys and non-numbers from stored metrics" do
    assert MetricCatalog.clean(%{"weight" => 70, "x" => 1, "waist" => "a"}) == %{"weight" => 70.0}
  end
end
