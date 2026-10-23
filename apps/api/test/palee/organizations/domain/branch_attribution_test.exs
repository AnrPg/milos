defmodule Palee.Organizations.Domain.BranchAttributionTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.BranchAttribution

  @kifisia "00000000-0000-0000-0000-00000000000a"
  @marousi "00000000-0000-0000-0000-00000000000b"
  @glyfada "00000000-0000-0000-0000-00000000000c"
  @active [@kifisia, @marousi, @glyfada]

  describe "home_branches/3" do
    test "the branch a person trained at most, among those their packages allow" do
      activity = [
        {"anna", @kifisia, 3},
        {"anna", @marousi, 5},
        {"nikos", @kifisia, 2},
        {"nikos", @marousi, 9}
      ]

      homes = BranchAttribution.home_branches(activity, %{"nikos" => [@kifisia]}, @active)

      assert homes == %{"anna" => @marousi, "nikos" => @kifisia}
    end

    test "ties go to the lowest id; inactive branches and zero counts are ignored" do
      activity = [
        {"anna", @marousi, 4},
        {"anna", @kifisia, 4},
        {"eleni", "archived", 10},
        {"eleni", @glyfada, 0}
      ]

      assert BranchAttribution.home_branches(activity, %{}, @active) == %{"anna" => @kifisia}
    end

    test "without activity: the only allowed branch, else no home" do
      allowed = %{"one" => [@glyfada], "two" => [@kifisia, @marousi], "everywhere" => :all}

      assert BranchAttribution.home_branches([], allowed, @active) == %{"one" => @glyfada}
    end
  end

  test "users_at/2, by_branch/1 and remainder/2" do
    homes = %{"anna" => @kifisia, "nikos" => @marousi, "eleni" => @kifisia}

    assert BranchAttribution.users_at(homes, :all) == nil
    assert Enum.sort(BranchAttribution.users_at(homes, [@kifisia])) == ["anna", "eleni"]
    assert BranchAttribution.users_at(homes, []) == []

    assert BranchAttribution.by_branch(homes)
           |> Map.new(fn {k, v} -> {k, Enum.sort(v)} end) ==
             %{@kifisia => ["anna", "eleni"], @marousi => ["nikos"]}

    assert BranchAttribution.remainder(10, [3, nil, 4]) == 3
    assert BranchAttribution.remainder(5, [3, 4]) == 0
  end

  test "activity_by_branch/1 and activity_counts/1" do
    rows = [{"anna", @kifisia, 2, 1}, {"nikos", @kifisia, 1, 3}, {"anna", @marousi, 0, 2}]

    assert BranchAttribution.activity_by_branch(rows) == %{
             @kifisia => %{check_ins: 3, attended: 4},
             @marousi => %{check_ins: 0, attended: 2}
           }

    assert BranchAttribution.activity_counts(rows) ==
             [{"anna", @kifisia, 3}, {"nikos", @kifisia, 4}, {"anna", @marousi, 2}]
  end
end
