defmodule Palee.Spaces.Domain.PhotoPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.Spaces.Domain.PhotoPolicy

  test "a room holds at most 30 photos or points" do
    assert PhotoPolicy.check_room(29) == :ok
    assert PhotoPolicy.check_room(30) == {:error, :space_photos_full}
  end

  test "reorder puts the listed ids first and keeps the rest in their order" do
    entries = Enum.map(~w(a b c d), &%{id: &1})

    assert PhotoPolicy.reorder(entries, ["c", "a", "zzz", "c"]) ==
             [{"c", 0}, {"a", 1}, {"b", 2}, {"d", 3}]
  end

  test "who sees what of a class's room" do
    off = %{floor_plans_in_classes: false}
    on = %{floor_plans_in_classes: true}
    shown = %{shown_in_classes: true}
    hidden = %{shown_in_classes: false}

    assert PhotoPolicy.class_view(off, hidden, true) == %{plan: true, photos: true}
    assert PhotoPolicy.class_view(off, shown, false) == %{plan: false, photos: false}
    assert PhotoPolicy.class_view(on, shown, false) == %{plan: true, photos: true}
    assert PhotoPolicy.class_view(on, hidden, false) == %{plan: false, photos: true}
    assert PhotoPolicy.class_view(on, nil, false) == %{plan: false, photos: true}
  end
end
