defmodule Palee.Interests.Domain.InterestsPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Interests.Domain.InterestsPolicy

  @known ~w(crossfit yoga running)

  test "keeps the person's order and drops duplicates" do
    assert {:ok, %{disciplines: ["yoga", "crossfit"], level: "advanced"}} =
             InterestsPolicy.normalize(
               %{"disciplines" => ["yoga", "crossfit", "yoga"], "level" => "advanced"},
               @known
             )
  end

  test "a level is optional but the key is required" do
    assert {:ok, %{level: nil}} =
             InterestsPolicy.normalize(%{"disciplines" => [], "level" => nil}, @known)

    assert {:error, [level: _]} = InterestsPolicy.normalize(%{"disciplines" => []}, @known)
  end

  test "rejects unknown keys and too many disciplines" do
    assert {:error, [disciplines: _]} =
             InterestsPolicy.normalize(%{"disciplines" => ["chess"], "level" => nil}, @known)

    many = Enum.map(1..13, &"d#{&1}")

    assert {:error, [disciplines: "at most 12"]} =
             InterestsPolicy.normalize(%{"disciplines" => many, "level" => nil}, many)
  end
end
