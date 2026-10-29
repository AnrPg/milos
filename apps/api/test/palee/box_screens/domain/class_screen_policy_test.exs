defmodule Palee.BoxScreens.Domain.ClassScreenPolicyTest do
  @moduledoc "ADR-253 update 2026-10-29: who may pin one class on a box screen."

  use ExUnit.Case, async: true

  alias Palee.BoxScreens.Domain.ClassScreenPolicy, as: Policy

  @today ~D[2027-02-08]
  @coach %{user_id: "coach-1", manages_screens: false, scope: :all}
  @other_coach %{user_id: "coach-2", manages_screens: false, scope: :all}
  @manager %{user_id: "owner-1", manages_screens: true, scope: :all}
  @class %{
    id: "slot-1",
    coach_user_id: "coach-1",
    location_id: "branch-a",
    cancelled_at: nil,
    date: @today
  }
  @room %{id: "s1", location_id: "branch-a"}
  @whole %{id: "s2", location_id: nil}
  @elsewhere %{id: "s3", location_id: "branch-b"}

  test "the class's coach may pin timer, leaderboard or WOD on its branch's or the whole box's screen" do
    for screen <- [@room, @whole], view <- ["timer", "leaderboard", "wod"] do
      assert Policy.may_pin?(@coach, @class, screen, view, @today) == :ok
    end

    assert Policy.may_pin?(@coach, @class, @room, "bookings", @today) ==
             {:error, :invalid_screen_override}

    assert Policy.screens(@coach, @class, [@room, @whole, @elsewhere], @today) == [@room, @whole]
  end

  test "a coach of another class is refused" do
    assert Policy.may_pin?(@other_coach, @class, @room, "timer", @today) == {:error, :forbidden}
    assert Policy.may_clear?(@other_coach, @class, @room, nil, @today) == {:error, :forbidden}
    assert Policy.screens(@other_coach, @class, [@room, @whole], @today) == []
    refute Policy.coaches_today?(%{user_id: nil}, %{@class | coach_user_id: nil}, @today)
  end

  test "only today, never a cancelled class, never another branch's screen" do
    assert Policy.may_pin?(@coach, %{@class | date: Date.add(@today, 1)}, @room, "timer", @today) ==
             {:error, :forbidden}

    assert Policy.may_pin?(@coach, %{@class | cancelled_at: ~U[2027-02-08 09:00:00Z]}, @room, "timer", @today) ==
             {:error, :forbidden}

    assert Policy.may_pin?(@coach, @class, @elsewhere, "timer", @today) == {:error, :forbidden}

    whole_box_class = %{@class | location_id: nil}
    assert Policy.may_pin?(@coach, whole_box_class, @elsewhere, "timer", @today) == :ok
  end

  test "a coach returns to automatic only from their own class or nothing pinned" do
    assert Policy.may_clear?(@coach, @class, @room, nil, @today) == :ok
    assert Policy.may_clear?(@coach, @class, @room, %{slot_id: "slot-1"}, @today) == :ok

    assert Policy.may_clear?(@coach, @class, @room, %{slot_id: nil}, @today) ==
             {:error, :forbidden}

    assert Policy.may_clear?(@coach, @class, @room, %{slot_id: "slot-9"}, @today) ==
             {:error, :forbidden}
  end

  test "screen managers keep their rights within their branches, any view" do
    assert Policy.views(@manager) == ~w(wod timer leaderboard bookings class)
    assert Policy.may_pin?(@manager, @class, @elsewhere, "bookings", @today) == :ok
    assert Policy.screens(@manager, @class, [@room, @whole, @elsewhere], @today) == [@room, @whole]
    assert Policy.may_clear?(@manager, @class, @room, %{slot_id: nil}, @today) == :ok

    branch_manager = %{@manager | scope: ["branch-a"]}
    assert Policy.may_pin?(branch_manager, @class, @room, "wod", @today) == :ok
    assert Policy.may_pin?(branch_manager, @class, @whole, "wod", @today) == {:error, :forbidden}
  end
end
