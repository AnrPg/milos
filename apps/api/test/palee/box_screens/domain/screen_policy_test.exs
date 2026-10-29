defmodule Palee.BoxScreens.Domain.ScreenPolicyTest do
  use ExUnit.Case, async: true

  alias Palee.BoxScreens.Domain.{ScreenPolicy, ScreenPrivacy}

  @now ~U[2027-02-09 10:00:00Z]

  test "a name is 1 to 60 characters, trimmed" do
    assert {:ok, "Αίθουσα 1"} = ScreenPolicy.name("  Αίθουσα   1 ")
    assert {:error, :invalid_screen_name} = ScreenPolicy.name("   ")
    assert {:error, :invalid_screen_name} = ScreenPolicy.name(String.duplicate("a", 61))
    assert {:error, :invalid_screen_name} = ScreenPolicy.name(nil)
  end

  test "a box has at most 20 screens" do
    assert :ok = ScreenPolicy.can_add?(19)
    assert {:error, :too_many_screens} = ScreenPolicy.can_add?(20)
  end

  test "an override names a view, maybe one of today's classes, maybe an end within a day" do
    slots = ["s1", "s2"]

    assert {:ok, %{override_view: "wod", override_slot_id: nil, override_until: nil}} =
             ScreenPolicy.override(%{view: "wod"}, slots, @now)

    assert {:ok, %{override_view: "class", override_slot_id: "s2"}} =
             ScreenPolicy.override(%{view: "class", slot_id: "s2"}, slots, @now)

    assert {:ok, %{override_until: ~U[2027-02-09 11:00:00Z]}} =
             ScreenPolicy.override(
               %{view: "timer", slot_id: "s1", until: "2027-02-09T13:00:00+02:00"},
               slots,
               @now
             )

    for bad <- [
          %{view: "tv"},
          %{view: "class"},
          %{view: "wod", slot_id: "elsewhere"},
          %{view: "wod", until: "2027-02-09T09:00:00Z"},
          %{view: "wod", until: "2027-02-10T10:00:01Z"},
          %{view: "wod", until: "soon"}
        ] do
      assert {:error, :invalid_screen_override} = ScreenPolicy.override(bad, slots, @now)
    end
  end

  test "an override with an end lapses at that end" do
    screen = %{
      override_view: "wod",
      override_slot_id: nil,
      override_until: ~U[2027-02-09 11:00:00Z]
    }

    assert %{view: "wod"} = ScreenPolicy.active_override(screen, @now)
    assert nil == ScreenPolicy.active_override(screen, ~U[2027-02-09 11:00:00Z])
    assert nil == ScreenPolicy.active_override(%{override_view: nil}, @now)
  end

  test "branch-scoped staff manage only their branches' screens" do
    assert ScreenPolicy.in_scope?(:all, nil)
    assert ScreenPolicy.in_scope?(["b1"], "b1")
    refute ScreenPolicy.in_scope?(["b1"], "b2")
    refute ScreenPolicy.in_scope?(["b1"], nil)
  end

  describe "privacy" do
    test "people are shown by the first word of their display name" do
      assert "Μαρία" == ScreenPrivacy.first_name("  Μαρία Παπαδοπούλου ")
      assert nil == ScreenPrivacy.first_name("   ")
      assert nil == ScreenPrivacy.first_name(nil)
    end

    test "hidden people, guests and trials are counted, never named" do
      at = fn minutes -> DateTime.add(@now, minutes, :second) end

      bookings = [
        %{user_id: "u1", status: :approved, kind: "member", inserted_at: at.(1)},
        %{user_id: "u2", status: :approved, kind: "member", inserted_at: at.(2)},
        %{user_id: "u3", status: :approved, kind: "guest", inserted_at: at.(3)},
        %{user_id: "u4", status: :approved, kind: "trial", inserted_at: at.(4)},
        %{user_id: "u5", status: :waitlisted, kind: "member", inserted_at: at.(5)},
        %{user_id: "u6", status: :cancelled, kind: "member", inserted_at: at.(6)}
      ]

      names = %{"u1" => "Νίκος Π.", "u2" => "Ελένη", "u3" => "Guest", "u4" => "Trial"}

      assert %{count: 4, capacity: 12, waitlist: 1, names: ["Νίκος"], unnamed: 3} ==
               ScreenPrivacy.bookings(bookings, 12, MapSet.new(["u2"]), names)

      assert ["u1", "u2"] == ScreenPrivacy.nameable_user_ids(bookings)
    end
  end
end
