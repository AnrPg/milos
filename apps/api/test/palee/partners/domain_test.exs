defmodule Palee.Partners.DomainTest do
  @moduledoc "ADR-169, ADR-280: public Partners rules, pure."

  use ExUnit.Case, async: true

  alias Palee.Partners.Domain.{
    BadgePolicy,
    DeckPolicy,
    MatchPolicy,
    MessagePolicy,
    ProfilePolicy,
    ReportPolicy,
    SwipePolicy
  }

  @now ~U[2026-11-16 10:00:00.000000Z]

  defp profile(user_id, attrs \\ %{}) do
    Map.merge(
      %{
        id: "p-#{user_id}",
        user_id: user_id,
        active: true,
        paused_at: nil,
        show_box: true,
        level: "intermediate",
        times: ["early"],
        goals: ["strength"],
        disciplines: [],
        about: nil,
        gender: nil,
        gender_preference: "any"
      },
      attrs
    )
  end

  describe "ProfilePolicy.normalize/3" do
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
      assert attrs.show_box
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

      assert {:error, :invalid_partner_show_box} =
               ProfilePolicy.normalize(%{
                 "level" => "beginner",
                 "times" => ["early"],
                 "goals" => ["strength"],
                 "show_box" => "yes"
               })
    end

    test "a partial update keeps the current values, show_box included" do
      current =
        profile("a", %{level: "advanced", times: ["evening"], goals: ["skills"], show_box: false})

      assert {:ok, attrs} = ProfilePolicy.normalize(%{active: false}, current)

      assert %{
               level: "advanced",
               times: ["evening"],
               goals: ["skills"],
               active: false,
               show_box: false
             } = attrs
    end
  end

  describe "ProfilePolicy: 18+, live, pause" do
    test "the first save needs the 18+ confirmation; a saved profile keeps it" do
      assert {:error, :partner_adult_required} = ProfilePolicy.adult_confirmation(nil, %{}, @now)

      assert {:error, :partner_adult_required} =
               ProfilePolicy.adult_confirmation(nil, %{"adult_confirmed" => "true"}, @now)

      assert {:ok, @now} =
               ProfilePolicy.adult_confirmation(nil, %{adult_confirmed: true}, @now)

      earlier = ~U[2026-10-01 08:00:00.000000Z]

      assert {:ok, ^earlier} =
               ProfilePolicy.adult_confirmation(%{adult_confirmed_at: earlier}, %{}, @now)
    end

    test "live means on and not paused; the Ρυθμίσεις switch pauses and resumes" do
      assert ProfilePolicy.live?(profile("a"))
      refute ProfilePolicy.live?(profile("b", %{active: false}))
      refute ProfilePolicy.live?(profile("c", %{paused_at: @now}))

      assert %{paused_at: @now} = ProfilePolicy.pause_changes(profile("a"), false, @now)
      earlier = ~U[2026-10-01 08:00:00.000000Z]

      assert %{paused_at: ^earlier} =
               ProfilePolicy.pause_changes(profile("a", %{paused_at: earlier}), false, @now)

      assert %{paused_at: nil} = ProfilePolicy.pause_changes(profile("a"), true, @now)
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
      off = profile("d", %{active: false, times: ["early"]})
      paused = profile("f", %{paused_at: @now, times: ["early"]})
      blocked = profile("e", %{times: ["early", "evening"], goals: ["strength", "skills"]})

      deck =
        DeckPolicy.deck(
          viewer,
          [level_only, adjacent, best, off, paused, blocked, viewer],
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

    test "disciplines narrow and weigh like goals" do
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
    end

    test "distance is one of 2, 5, 10, 25 km, 10 by default (ADR-280)" do
      assert DeckPolicy.distances_km() == [2, 5, 10, 25]
      assert DeckPolicy.filters(%{}).within_km == 10
      assert DeckPolicy.filters(nil).within_km == 10
      assert DeckPolicy.filters(%{"within_km" => "5"}).within_km == 5
      assert DeckPolicy.filters(%{"within_km" => 25}).within_km == 25
      assert DeckPolicy.filters(%{"within_km" => 3}).within_km == 10
      assert DeckPolicy.filters(%{"within_km" => "far"}).within_km == 10
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

    test "one person: swipeable only when live, compatible and not excluded" do
      viewer = profile("v", %{gender: "woman", gender_preference: "women"})
      assert DeckPolicy.swipeable?(viewer, profile("a", %{gender: "woman"}), MapSet.new())
      refute DeckPolicy.swipeable?(viewer, profile("b", %{gender: "man"}), MapSet.new())
      refute DeckPolicy.swipeable?(viewer, profile("c", %{gender: "woman"}), MapSet.new(["c"]))
      refute DeckPolicy.swipeable?(viewer, viewer, MapSet.new())
    end
  end

  describe "BadgePolicy" do
    test "box while a membership is active and show_box is on, else member" do
      assert %{kind: "box", box_name: "CrossFit Kifisia"} =
               BadgePolicy.badge(%{method: "membership", box_name: "CrossFit Kifisia"}, true)

      assert %{kind: "member", box_name: nil} =
               BadgePolicy.badge(%{method: "membership", box_name: "CrossFit Kifisia"}, false)

      # A sponsors-verified person who joined a box shows the membership.
      assert %{kind: "box"} = BadgePolicy.badge(%{method: "sponsors", box_name: "Box"}, nil)
    end

    test "verified for an ex-member, sponsors for path 2, nothing when not verified" do
      assert %{kind: "verified", box_name: nil} =
               BadgePolicy.badge(%{method: "membership", box_name: nil}, true)

      assert %{kind: "sponsors", box_name: nil} =
               BadgePolicy.badge(%{method: "sponsors", box_name: nil}, true)

      assert BadgePolicy.badge(nil, true) == nil
      assert BadgePolicy.kinds() == ~w(box member verified sponsors)
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

    test "ending once, for a known reason; ended conversations are read-only" do
      match = %{status: "active"}
      assert MatchPolicy.end_reasons() == ~w(unmatched blocked reported suspended)

      assert {:ok, %{status: "ended", end_reason: "suspended", ended_by_id: nil}} =
               MatchPolicy.end_changes(match, "suspended", nil, @now)

      assert {:error, :invalid_end_reason} = MatchPolicy.end_changes(match, "left", "a", @now)

      assert {:error, :partner_match_ended} =
               MatchPolicy.end_changes(%{status: "ended"}, "unmatched", "a", @now)

      assert :ok = MatchPolicy.can_message?(match)
      assert {:error, :partner_match_read_only} = MatchPolicy.can_message?(%{status: "ended"})
      assert MatchPolicy.read_only?(%{status: "ended"})
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

    test "a plan keeps a snapshot of a class, event or trial" do
      id = Ecto.UUID.generate()

      assert {:ok, snapshot} =
               MessagePolicy.plan_snapshot(%{
                 kind: "event",
                 id: id,
                 title: "Hyrox Athens",
                 starts_at: @now,
                 place: "Γήπεδο"
               })

      assert snapshot == %{
               "kind" => "event",
               "id" => id,
               "title" => "Hyrox Athens",
               "starts_at" => "2026-11-16T10:00:00.000000Z",
               "place" => "Γήπεδο"
             }

      assert {:ok, %{"place" => nil}} =
               MessagePolicy.plan_snapshot(%{
                 "kind" => "class",
                 "id" => id,
                 "title" => "WOD",
                 "starts_at" => "2026-11-16T10:00:00Z",
                 "place" => nil
               })
    end

    test "an unknown kind, a bad id or a missing start is not a plan" do
      id = Ecto.UUID.generate()
      base = %{kind: "trial", id: id, title: "Trial", starts_at: @now, place: nil}
      assert {:ok, _snapshot} = MessagePolicy.plan_snapshot(base)

      for broken <- [
            %{base | kind: "party"},
            %{base | id: "nope"},
            %{base | title: ""},
            %{base | starts_at: "tomorrow"},
            nil
          ] do
        assert {:error, :invalid_partner_plan} = MessagePolicy.plan_snapshot(broken)
      end
    end
  end

  describe "ReportPolicy" do
    test "a report names someone else, a known reason and a short note" do
      me = Ecto.UUID.generate()
      other = Ecto.UUID.generate()

      assert {:ok, %{reporter_id: ^me, target_id: ^other, reason: "minor", note: "looks 15"}} =
               ReportPolicy.normalize(me, %{target_id: other, reason: "minor", note: " looks 15 "})

      assert {:error, :cannot_report_self} =
               ReportPolicy.normalize(me, %{target_id: me, reason: "fake"})

      assert {:error, :invalid_partner_report_reason} =
               ReportPolicy.normalize(me, %{"target_id" => other, "reason" => "spam"})

      assert {:error, :partner_report_note_too_long} =
               ReportPolicy.normalize(me, %{
                 target_id: other,
                 reason: "other",
                 note: String.duplicate("a", 501)
               })

      assert {:error, :not_found} = ReportPolicy.normalize(me, %{target_id: "x", reason: "other"})
    end

    test "decisions: suspend actions, dismiss dismisses, once" do
      assert {:ok, %{decision: "suspend", note: nil}} =
               ReportPolicy.normalize_decision(%{"decision" => "suspend"})

      assert {:error, :invalid_partner_decision} =
               ReportPolicy.normalize_decision(%{decision: "hide"})

      assert {:ok, %{status: "actioned", decided_by_id: "v", decided_at: @now}} =
               ReportPolicy.decision_changes(%{status: "open"}, "suspend", "v", nil, @now)

      assert {:ok, %{status: "dismissed"}} =
               ReportPolicy.decision_changes(%{status: "open"}, "dismiss", "v", "ok", @now)

      assert {:error, :partner_report_decided} =
               ReportPolicy.decision_changes(%{status: "dismissed"}, "suspend", "v", nil, @now)

      assert ReportPolicy.suspends?("suspend")
      refute ReportPolicy.suspends?("dismiss")
      assert ReportPolicy.suspension_profile_changes() == %{active: false}
      assert ReportPolicy.suspension_end_reason() in MatchPolicy.end_reasons()
    end
  end
end
