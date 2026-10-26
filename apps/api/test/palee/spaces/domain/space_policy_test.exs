defmodule Palee.Spaces.Domain.SpacePolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Spaces.Domain.SpacePolicy

  @t0 ~U[2026-12-01 10:00:00Z]

  defp at(minutes), do: DateTime.add(@t0, minutes * 60, :second)

  describe "editable fields" do
    test "front desk changes details only; managers change everything" do
      assert SpacePolicy.check_fields(%{name: "Cardio", directions: "Upstairs"}, :details) == :ok
      assert SpacePolicy.check_fields(%{"description" => "Big"}, :details) == :ok
      assert SpacePolicy.check_fields(%{area: nil}, :details) == {:error, :forbidden}
      assert SpacePolicy.check_fields(%{location_id: nil}, :details) == {:error, :forbidden}

      assert SpacePolicy.check_fields(
               %{name: "A", tasks: [], floor_plan_id: nil, area: nil, location_id: nil},
               :manage
             ) == :ok
    end
  end

  describe "areas" do
    test "a polygon of 3 to 32 normalized points is kept, rounded" do
      assert {:ok, %{"points" => [[0.1235, +0.0], [1.0, 0.5], [0.5, 1.0]]}} =
               SpacePolicy.normalize_area(%{points: [[0.123456, 0], [1, 0.5], [0.5, 1]]})

      assert SpacePolicy.normalize_area(nil) == {:ok, nil}
    end

    test "points outside the plan, too few or too many are refused" do
      for area <- [
            %{"points" => [[0, 0], [1, 1]]},
            %{"points" => [[0, 0], [1.2, 0], [1, 1]]},
            %{"points" => [[0, 0], [-0.1, 0], [1, 1]]},
            %{"points" => List.duplicate([0.5, 0.5], 33)},
            %{"points" => [[0, 0], ["x", 0], [1, 1]]},
            %{"shape" => "rect"},
            "rect"
          ] do
        assert SpacePolicy.normalize_area(area) == {:error, :invalid_space_area}, inspect(area)
      end
    end

    test "a rectangle is four points" do
      assert {:ok, %{"points" => [[0.1, 0.2], [0.4, 0.2], [0.4, 0.5], [0.1, 0.5]]}} =
               0.1 |> SpacePolicy.rectangle(0.2, 0.3, 0.3) |> SpacePolicy.normalize_area()
    end
  end

  describe "unavailability" do
    test "a window must end after it starts" do
      assert SpacePolicy.validate_window(at(0), at(60)) == :ok
      assert SpacePolicy.validate_window(at(60), at(60)) == {:error, :invalid_unavailability}
      assert SpacePolicy.validate_window(nil, at(60)) == {:error, :invalid_unavailability}
    end

    test "a class that overlaps a window is refused, one that only touches it is not" do
      window = %{starts_at: at(60), ends_at: at(180), reason: "Floor repair"}

      assert {:error, {:space_unavailable, ^window}} =
               SpacePolicy.check_available([window], at(30), 60)

      assert {:error, {:space_unavailable, ^window}} =
               SpacePolicy.check_available([window], at(170), 60)

      assert SpacePolicy.check_available([window], at(0), 60) == :ok
      assert SpacePolicy.check_available([window], at(180), 60) == :ok
      assert SpacePolicy.check_available([], at(90), 60) == :ok
    end
  end

  describe "overlapping classes" do
    test "classes sharing a space at overlapping times are flagged, other spaces are not" do
      classes = [
        %{id: "a", space_id: "s1", scheduled_at: at(0), duration_minutes: 60},
        %{id: "b", space_id: "s1", scheduled_at: at(30), duration_minutes: 60},
        %{id: "c", space_id: "s1", scheduled_at: at(90), duration_minutes: 30},
        %{id: "d", space_id: "s2", scheduled_at: at(0), duration_minutes: 60},
        %{id: "e", space_id: nil, scheduled_at: at(0), duration_minutes: 60},
        %{id: "f", space_id: nil, scheduled_at: at(0), duration_minutes: 60}
      ]

      assert SpacePolicy.overlapping_ids(classes) == MapSet.new(["a", "b"])
    end
  end

  describe "where a class may use a space" do
    test "usable spaces and branches" do
      assert SpacePolicy.usable(%{archived_at: nil}) == :ok
      assert SpacePolicy.usable(%{archived_at: @t0}) == {:error, :space_archived}
      assert SpacePolicy.usable(nil) == {:error, :space_not_found}

      assert SpacePolicy.same_branch(%{location_id: "kifisia"}, "kifisia") == :ok
      assert SpacePolicy.same_branch(%{location_id: nil}, "kifisia") == :ok

      assert SpacePolicy.same_branch(%{location_id: "kifisia"}, "marousi") ==
               {:error, :space_wrong_branch}

      assert SpacePolicy.same_branch(%{location_id: "kifisia"}, nil) ==
               {:error, :space_wrong_branch}
    end
  end
end
