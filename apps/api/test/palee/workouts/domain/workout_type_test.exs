defmodule Palee.Workouts.Domain.WorkoutTypeTest do
  use ExUnit.Case, async: true

  alias Palee.Organizations.Domain.BoxProfilePolicy
  alias Palee.Workouts.Domain.WorkoutType

  # ADR-275: one fixed list of workout kinds, grouped in families.
  test "keeps the original six kinds" do
    for type <- ~w(crossfit strength gymnastics aerobics flexibility recovery) do
      assert WorkoutType.valid?(type)
    end
  end

  test "has martial arts and dance kinds in their own families" do
    assert WorkoutType.family("muay_thai") == "combat"
    assert WorkoutType.family(:bjj_grappling) == "combat"
    assert WorkoutType.family("pole_aerial") == "dance"
    assert WorkoutType.family("karaoke") == nil
    refute WorkoutType.valid?("karaoke")
    refute WorkoutType.valid?(nil)
  end

  test "lists every kind once, as strings and atoms alike" do
    keys = WorkoutType.keys()
    assert keys == Enum.uniq(keys)
    assert Enum.map(WorkoutType.values(), &Atom.to_string/1) == keys
  end

  test "shares its keys with the box profile's disciplines" do
    # Every kind except the original aerobics and flexibility names a discipline.
    assert (WorkoutType.keys() -- ["aerobics", "flexibility"]) -- BoxProfilePolicy.disciplines() ==
             []
  end
end
