defmodule Palee.Nutrition.Domain.PortionPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Nutrition.Domain.PortionPolicy

  test "grams become hand portions, rounded to halves; the coach's own portions win" do
    assert PortionPolicy.from_grams(%{protein_grams: 180, carbs_grams: 210, fat_grams: 65}) ==
             %{"protein" => 7, "carbs" => 8.5, "fat" => 6.5}

    assert PortionPolicy.effective(%{protein_grams: nil, carbs_grams: nil, fat_grams: nil}) == nil

    assert PortionPolicy.effective(%{protein_grams: 180, portion_targets: %{"veg" => 5}}) ==
             %{"veg" => 5}
  end

  test "coach portions are halves up to 20 of the four hands" do
    assert {:ok, %{"protein" => 6, "carbs" => 4.5}} =
             PortionPolicy.validate(%{protein: 6, carbs: 4.5, fat: nil})

    assert {:ok, nil} = PortionPolicy.validate(%{})
    assert {:error, _} = PortionPolicy.validate(%{protein: 6.25})
    assert {:error, _} = PortionPolicy.validate(%{kcal: 2})
    assert {:error, _} = PortionPolicy.validate(%{fat: 21})
  end

  test "logged portions add up across meals" do
    assert PortionPolicy.logged([
             %{"portions" => %{"protein" => 1, "carbs" => 0.5}},
             %{"portions" => %{"protein" => 1.5}},
             %{"slot" => "snack"}
           ]) == %{"protein" => 2.5, "carbs" => 0.5, "veg" => 0, "fat" => 0}
  end
end
