defmodule Palee.Partners.DomainTest do
  @moduledoc "ADR-169: Partners rules, pure."

  use ExUnit.Case, async: true

  alias Palee.Partners.Domain.{
    ClubEligibility,
    DeckPolicy,
    MatchPolicy,
    MessagePolicy,
    ProfilePolicy,
    SessionPolicy,
    SwipePolicy
  }

  @now ~U[2026-11-16 10:00:00.000000Z]

  defp profile(user_id, attrs \\ %{}) do
    Map.merge(
      %{
        id: "p-#{user_id}",
        user_id: user_id,
        active: true,
        suspended_at: nil,
        level: "intermediate",
        times: ["early"],
        goals: ["strength"],
        about: nil,
        gender: nil,
        gender_preference: "any"
      },
      attrs
    )
  end

  describe "ProfilePolicy.normalize/2" do
    test "keeps lists in canonical order, deduplicated, and trims about" do
      assert {:ok, attrs} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => ["weekend", "early", "early"],
                 "goals" => ["skills", "strength"],
                 "about" => "  Hyrox in November  "
               })

      assert attrs.times == ["early", "weekend"]
      assert attrs.goals == ["strength", "skills"]
      assert attrs.about == "Hyrox in November"
      assert attrs.gender_preference == "any"
      assert attrs.active
    end

    test "rejects missing or unknown values and more than three goals" do
      assert {:error, :invalid_partner_level} = ProfilePolicy.normalize(%{"times" => ["early"]})

      assert {:error, :invalid_partner_times} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => [],
                 "goals" => ["strength"]
               })

      assert {:error, :invalid_partner_goals} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => ["early"],
                 "goals" => ["strength", "skills", "competition", "consistency"]
               })

      assert {:error, :partner_about_too_long} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => ["early"],
                 "goals" => ["strength"],
                 "about" => String.duplicate("a", 141)
               })

      assert {:error, :invalid_partner_gender_preference} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => ["early"],
                 "goals" => ["strength"],
                 "gender_preference" => "dates"
               })
    end

    test "a partial update keeps the current values" do
      current = profile("a", %{level: "advanced", times: ["evening"], goals: ["skills"]})
      assert {:ok, attrs} = ProfilePolicy.normalize(%{"active" => false}, current)
      assert %{level: "advanced", times: ["evening"], goals: ["skills"], active: false} = attrs
    end

    test "a suspended profile can't be switched on" do
      suspended = profile("a", %{suspended_at: @now})

      assert {:error, :partner_profile_suspended} =
               ProfilePolicy.check_activation(suspended, true)

      assert :ok = ProfilePolicy.check_activation(suspended, false)
      refute ProfilePolicy.live?(suspended)
      refute ProfilePolicy.live?(profile("b", %{active: false}))
      assert ProfilePolicy.live?(profile("c"))
    end
  end

  describe "ClubEligibility" do
    test "only clubs whose members the gym verified offer Partners" do
      assert ClubEligibility.verified?(%{kind: "gym"})
      assert ClubEligibility.verified?(%{kind: "pt_squad"})
      assert ClubEligibility.verified?(%{kind: "season"})
      assert ClubEligibility.verified?(%{kind: "open", join_policy: "approval"})
      assert ClubEligibility.verified?(%{kind: "open", join_policy: "invite"})
      refute ClubEligibility.verified?(%{kind: "open", join_policy: "open"})
      refute ClubEligibility.verified?(%{kind: "gym", archived_at: @now})
      refute ClubEligibility.verified?(%{kind: "member_group"})
    end

    test "the gym's switch wins" do
      assert {:error, :partners_disabled} = ClubEligibility.check(%{kind: "gym"}, false)

      assert {:error, :partners_not_offered} =
               ClubEligibility.check(%{kind: "open", join_policy: "open"}, true)

      assert :ok = ClubEligibility.check(%{kind: "gym"}, true)
    end
  end

  describe "DeckPolicy" do
    test "gender preferences hold both ways; unset gender only meets `any`" do
      woman_any = profile("a", %{gender: "woman"})
      woman_women = profile("b", %{gender: "woman", gender_preference: "women"})
      man_any = profile("c", %{gender: "man"})
      unset_any = profile("d")

      assert DeckPolicy.gender_compatible?(woman_any, man_any)
      assert DeckPolicy.gender_compatible?(woman_women, woman_any)
      refute DeckPolicy.gender_compatible?(woman_women, man_any)
      refute DeckPolicy.gender_compatible?(man_any, woman_women)
      refute DeckPolicy.gender_compatible?(woman_women, unset_any)
      assert DeckPolicy.gender_compatible?(unset_any, man_any)
    end

    test "orders by what the two share, ties by id, and leaves out the excluded" do
      viewer = profile("v", %{times: ["early", "evening"], goals: ["strength", "skills"]})
      best = profile("b", %{times: ["early", "evening"], goals: ["strength"]})
      level_only = profile("a", %{times: ["midday"], goals: ["conditioning"]})
      adjacent = profile("c", %{level: "advanced", times: ["midday"], goals: ["conditioning"]})
      paused = profile("d", %{active: false, times: ["early"]})
      blocked = profile("e", %{times: ["early", "evening"], goals: ["strength", "skills"]})

      deck =
        DeckPolicy.deck(
          viewer,
          [level_only, adjacent, best, paused, blocked, viewer],
          MapSet.new(["e"]),
          DeckPolicy.filters(%{})
        )

      assert Enum.map(deck, fn {p, _shared} -> p.user_id end) == ["b", "a", "c"]
      {_best, shared} = hd(deck)

      assert shared == %{
               times: ["early", "evening"],
               goals: ["strength"],
               disciplines: [],
               same_level: true
             }
    end

    test "filters narrow by time, level and goal; unknown filter values are ignored" do
      viewer = profile("v")
      evening = profile("a", %{times: ["evening"]})
      early = profile("b")

      deck =
        DeckPolicy.deck(
          viewer,
          [evening, early],
          MapSet.new(),
          DeckPolicy.filters(%{"time" => "evening"})
        )

      assert Enum.map(deck, fn {p, _} -> p.user_id end) == ["a"]
      assert DeckPolicy.filters(%{"level" => "pro"}).level == nil
    end

    test "disciplines narrow and weigh like goals; distances are fixed steps (ADR-197)" do
      viewer = profile("v", %{disciplines: ["running"]})
      runner = profile("a", %{disciplines: ["running", "yoga"]})
      lifter = profile("b", %{disciplines: ["powerlifting"]})

      assert [{%{user_id: "a"}, %{disciplines: ["running"]}}, {%{user_id: "b"}, _}] =
               DeckPolicy.deck(viewer, [lifter, runner], MapSet.new(), DeckPolicy.filters(%{}))

      assert [{%{user_id: "b"}, _}] =
               DeckPolicy.deck(
                 viewer,
                 [lifter, runner],
                 MapSet.new(),
                 DeckPolicy.filters(%{"discipline" => "powerlifting"})
               )

      assert DeckPolicy.filters(%{"within_km" => "5"}).within_km == 5
      assert DeckPolicy.filters(%{"within_km" => 3}).within_km == nil
    end

    test "likes stay out for good, passes for 30 days" do
      swipes = [
        %{
          target_id: "liked",
          direction: "like",
          updated_at: DateTime.add(@now, -90 * 86_400, :second)
        },
        %{
          target_id: "recent_pass",
          direction: "pass",
          updated_at: DateTime.add(@now, -3 * 86_400, :second)
        },
        %{
          target_id: "old_pass",
          direction: "pass",
          updated_at: DateTime.add(@now, -31 * 86_400, :second)
        }
      ]

      assert DeckPolicy.swiped_ids(swipes, @now) == MapSet.new(["liked", "recent_pass"])
    end
  end

  describe "SwipePolicy" do
    test "200 swipes in 24 hours, then no more" do
      assert :ok = SwipePolicy.check_rate(199)
      assert {:error, :partner_swipe_limit} = SwipePolicy.check_rate(200)
      assert SwipePolicy.remaining(250) == 0
      assert {:error, :invalid_direction} = SwipePolicy.normalize_direction("super_like")
    end

    test "only a like answered by a like is mutual" do
      assert SwipePolicy.mutual?("like", %{direction: "like"})
      refute SwipePolicy.mutual?("like", %{direction: "pass"})
      refute SwipePolicy.mutual?("like", nil)
      refute SwipePolicy.mutual?("pass", %{direction: "like"})
    end
  end

  describe "MatchPolicy" do
    test "pairs are ordered; read marks and the other side follow the viewer" do
      assert MatchPolicy.pair("b", "a") == {"a", "b"}
      match = %{user_a_id: "a", user_b_id: "b", status: "active", a_read_at: @now, b_read_at: nil}
      assert MatchPolicy.other(match, "a") == "b"
      assert MatchPolicy.read_field(match, "b") == :b_read_at
      assert MatchPolicy.read_at(match, "a") == @now
      refute MatchPolicy.party?(match, "c")
    end

    test "ending once; the conversation is read-only once ended or someone left" do
      match = %{status: "active"}

      assert {:ok, %{status: "ended", end_reason: "blocked"}} =
               MatchPolicy.end_changes(match, "blocked", "a", @now)

      assert {:error, :partner_match_ended} =
               MatchPolicy.end_changes(%{status: "ended"}, "unmatched", "a", @now)

      assert :ok = MatchPolicy.can_message?(match, true)
      assert {:error, :partner_match_read_only} = MatchPolicy.can_message?(match, false)
      assert MatchPolicy.read_only?(%{status: "ended"}, true)
    end
  end

  describe "MessagePolicy" do
    test "bodies, notes and cursors" do
      assert {:ok, "hi"} = MessagePolicy.normalize_body("  hi ")
      assert {:error, :message_body_required} = MessagePolicy.normalize_body("   ")
      assert {:ok, nil} = MessagePolicy.normalize_note("  ")
      row = %{inserted_at: @now, id: Ecto.UUID.generate()}
      assert {:ok, ^row} = row |> MessagePolicy.encode_cursor() |> MessagePolicy.decode_cursor()
      assert {:error, :invalid_cursor} = MessagePolicy.decode_cursor("nope")
    end

    test "a plan keeps the class's name and start" do
      slot = %{
        id: "c1",
        name: nil,
        class_type: %{name: "CrossFit"},
        scheduled_at: @now,
        duration_minutes: 60
      }

      assert MessagePolicy.plan_snapshot(slot) == %{
               "class_id" => "c1",
               "name" => "CrossFit",
               "scheduled_at" => "2026-11-16T10:00:00.000000Z",
               "duration_minutes" => 60
             }
    end
  end

  describe "SessionPolicy" do
    test "periods in the gym's zone; weekends are weekend" do
      # 05:30 UTC is 07:30 in Athens on a Monday.
      assert SessionPolicy.period(~U[2026-11-16 05:30:00Z], "Europe/Athens") == "early"
      assert SessionPolicy.period(~U[2026-11-16 16:30:00Z], "Europe/Athens") == "evening"
      assert SessionPolicy.period(~U[2026-11-21 08:00:00Z], "Europe/Athens") == "weekend"
    end

    test "booked by either first, then shared times, then the soonest; full classes only if booked" do
      slot = fn id, at, spots, bookings ->
        %{id: id, scheduled_at: at, spots_remaining: spots, bookings: bookings}
      end

      slots = [
        slot.("past", ~U[2026-11-16 09:00:00Z], 5, []),
        slot.("soon", ~U[2026-11-16 12:00:00Z], 5, []),
        slot.("early_shared", ~U[2026-11-17 05:30:00Z], 5, []),
        slot.("full", ~U[2026-11-17 12:00:00Z], 0, []),
        slot.("booked", ~U[2026-11-18 12:00:00Z], 0, [
          %{user_id: "b", status: :approved},
          %{user_id: "x", status: :approved}
        ])
      ]

      ranked = SessionPolicy.suggestions(slots, ["a", "b"], ["early"], "Europe/Athens", @now)

      assert Enum.map(ranked, & &1.slot.id) == ["booked", "early_shared", "soon"]
      assert hd(ranked).booked == ["b"]
    end
  end
end
