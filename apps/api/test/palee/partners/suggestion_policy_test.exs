defmodule Palee.Partners.Domain.SuggestionPolicyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Palee.Partners.Domain.SuggestionPolicy

  # Monday 2027-03-01 10:00 UTC.
  @now ~U[2027-03-01 10:00:00Z]
  @me "00000000-0000-0000-0000-00000000000a"
  @other "00000000-0000-0000-0000-00000000000b"
  @athens "Europe/Athens"
  # Syntagma and two points about 2 km and 15 km away.
  @centre {37.9755, 23.7348}
  @near {37.9935, 23.7348}
  @far {38.1105, 23.7348}

  defp people(overrides \\ %{}) do
    [
      Map.merge(
        %{id: @me, times: ~w(evening weekend), level: "intermediate", point: @centre},
        Map.get(overrides, :me, %{})
      ),
      Map.merge(
        %{id: @other, times: ~w(evening midday), level: "intermediate", point: @centre},
        Map.get(overrides, :other, %{})
      )
    ]
  end

  defp activity(attrs) do
    Map.merge(
      %{
        kind: "event",
        id: "event-#{System.unique_integer([:positive])}",
        title: "Run club",
        starts_at: DateTime.add(@now, 86_400, :second),
        ends_at: nil,
        time_zone: @athens,
        point: @near,
        level: nil,
        capacity_left: 5,
        cancelled: false,
        organiser_id: nil,
        booked_by: [],
        place: "Park"
      },
      Map.new(attrs)
    )
  end

  defp suggest(candidates, opts \\ []) do
    SuggestionPolicy.suggest(%{
      people: Keyword.get(opts, :people, people()),
      candidates: candidates,
      blocked_ids: Keyword.get(opts, :blocked_ids, []),
      now: Keyword.get(opts, :now, @now)
    })
  end

  defp ids(suggestions), do: Enum.map(suggestions, & &1.id)

  describe "hard filters" do
    test "drops full activities unless both are already in" do
      full = activity(id: "full", capacity_left: 0)
      one_in = activity(id: "one-in", capacity_left: 0, booked_by: [@me])
      both_in = activity(id: "both-in", capacity_left: 0, booked_by: [@me, @other])
      unlimited = activity(id: "unlimited", capacity_left: nil)

      assert ids(suggest([full, one_in, both_in, unlimited])) == ["both-in", "unlimited"]
    end

    test "drops cancelled activities" do
      assert suggest([activity(cancelled: true)]) == []
    end

    test "drops started activities and those beyond 7 days" do
      started = activity(id: "started", starts_at: @now)
      past = activity(id: "past", starts_at: DateTime.add(@now, -60, :second))
      edge = activity(id: "edge", starts_at: DateTime.add(@now, 7 * 86_400, :second))
      late = activity(id: "late", starts_at: DateTime.add(@now, 7 * 86_400 + 1, :second))

      assert ids(suggest([started, past, edge, late])) == ["edge"]
    end

    test "keeps only activities within each person's distance (default 10 km)" do
      assert ids(suggest([activity(id: "near"), activity(id: "far", point: @far)])) == ["near"]

      wide = people(%{me: %{max_km: 25}, other: %{max_km: 25}})
      assert "far" in ids(suggest([activity(id: "far", point: @far)], people: wide))

      narrow = people(%{other: %{max_km: 1}})
      assert suggest([activity(id: "near")], people: narrow) == []
    end

    test "an unknown distance passes only for a shared box's class" do
      no_point = %{point: nil}

      assert ids(
               suggest([
                 activity(Map.merge(no_point, %{id: "class", kind: "class"})),
                 activity(Map.merge(no_point, %{id: "event"})),
                 activity(Map.merge(no_point, %{id: "trial", kind: "trial"}))
               ])
             ) == ["class"]
    end

    test "uses given distances when the place has no point" do
      given = activity(id: "given", point: nil, distances_km: [1.24, 3.06])
      too_far = activity(id: "too-far", point: nil, distances_km: [1.0, 12.0])

      assert [%{id: "given", distances_km: [1.2, 3.1]}] = suggest([given, too_far])
    end

    test "the level fits both people" do
      beginners = activity(id: "beginners", level: "beginner")
      advanced = activity(id: "advanced", level: "advanced")
      ranged = activity(id: "ranged", levels: ["advanced"])

      mixed = people(%{me: %{level: "beginner"}, other: %{level: "advanced"}})
      assert suggest([beginners, advanced, ranged], people: mixed) == []

      both_advanced = people(%{me: %{level: "advanced"}, other: %{level: "advanced"}})

      assert Enum.sort(ids(suggest([beginners, advanced, ranged], people: both_advanced))) ==
               ["advanced", "ranged"]

      assert ids(suggest([activity(id: "all", level: "all_levels")], people: mixed)) == ["all"]
    end

    test "a person without a level fits any level" do
      unknown = people(%{me: %{level: nil}})
      assert ids(suggest([activity(id: "adv", level: "advanced")], people: unknown)) == ["adv"]
    end

    test "drops activities whose organiser either person blocked" do
      blocked = activity(id: "blocked", organiser_id: "coach-1")
      fine = activity(id: "fine", organiser_id: "coach-2")

      assert ids(suggest([blocked, fine], blocked_ids: ["coach-1"])) == ["fine"]
    end

    test "drops unknown kinds" do
      assert suggest([activity(kind: "party")]) == []
    end
  end

  describe "order" do
    test "booked by both, then by one, before anything else" do
      none = activity(id: "none", starts_at: DateTime.add(@now, 3600, :second))
      one = activity(id: "one", booked_by: [@other], starts_at: DateTime.add(@now, 86_400 * 3))

      both =
        activity(id: "both", booked_by: [@me, @other], starts_at: DateTime.add(@now, 86_400 * 5))

      assert ids(suggest([none, one, both])) == ["both", "one", "none"]
    end

    test "then by time slots both chose, in the activity's own zone" do
      # 17:30 UTC on a Monday is 19:30 in Athens (evening, shared) but
      # afternoon in UTC.
      evening = ~U[2027-03-01 17:30:00Z]
      sooner = activity(id: "sooner", starts_at: DateTime.add(@now, 3600, :second))
      athens = activity(id: "athens", starts_at: evening, time_zone: @athens)
      utc = activity(id: "utc", starts_at: evening, time_zone: "Etc/UTC")

      assert ids(suggest([sooner, utc, athens])) == ["athens", "sooner", "utc"]
    end

    test "then by fairness: the smaller of the farther distances" do
      at = DateTime.add(@now, 86_400, :second)
      lopsided = activity(id: "lopsided", starts_at: at, point: nil, distances_km: [0.5, 8.0])
      fair = activity(id: "fair", starts_at: at, point: nil, distances_km: [4.0, 4.0])

      assert ids(suggest([lopsided, fair])) == ["fair", "lopsided"]
    end

    test "then the sooner start, then the key" do
      at = DateTime.add(@now, 86_400, :second)
      later = activity(id: "a-later", starts_at: DateTime.add(at, 60, :second))
      b = activity(id: "b", starts_at: at)
      a = activity(id: "a", starts_at: at)

      assert ids(suggest([later, b, a])) == ["a", "b", "a-later"]
    end

    test "at most three" do
      assert length(suggest(for i <- 1..10, do: activity(id: "e#{i}"))) == 3
    end
  end

  describe "reasons and shape" do
    test "carry booked, shared slots, level fit, distances and the key" do
      saturday_evening = ~U[2027-03-06 17:00:00Z]

      [suggestion] =
        suggest(
          [
            activity(
              id: "x",
              kind: "class",
              booked_by: [@other, "stranger"],
              starts_at: saturday_evening,
              level: "all_levels"
            )
          ],
          people: people(%{other: %{times: ~w(evening weekend)}})
        )

      assert suggestion.key == "class:x"
      assert suggestion.booked_by == [@other]

      assert suggestion.reasons == [
               "one_booked",
               "shared_time:evening",
               "shared_time:weekend",
               "level_fit",
               "near_both"
             ]

      assert [a, b] = suggestion.distances_km
      assert a == b and a > 1.5 and a < 2.5
      refute Map.has_key?(suggestion, :point)
    end

    test "never says who else booked" do
      [suggestion] = suggest([activity(booked_by: ["stranger", @me])])
      assert suggestion.booked_by == [@me]
    end
  end

  describe "slots_of/2" do
    test "hour slot in the local zone, plus weekend" do
      assert SuggestionPolicy.slots_of(~U[2027-03-01 05:00:00Z], @athens) == ["early"]
      assert SuggestionPolicy.slots_of(~U[2027-03-01 10:00:00Z], @athens) == ["midday"]
      assert SuggestionPolicy.slots_of(~U[2027-03-01 14:00:00Z], @athens) == ["afternoon"]
      assert SuggestionPolicy.slots_of(~U[2027-03-01 16:00:00Z], @athens) == ["evening"]
      assert SuggestionPolicy.slots_of(~U[2027-03-06 07:00:00Z], @athens) == ["midday", "weekend"]
      assert SuggestionPolicy.slots_of(~U[2027-03-01 16:00:00Z], nil) == ["afternoon"]
    end
  end

  describe "keys and feedback" do
    test "parse_key/1 round-trips key/1" do
      assert SuggestionPolicy.parse_key(SuggestionPolicy.key(%{kind: "trial", id: "abc"})) ==
               {:ok, {"trial", "abc"}}

      assert SuggestionPolicy.parse_key("party:abc") == :error
      assert SuggestionPolicy.parse_key(nil) == :error
    end

    test "feedback/1 checks the key and the reason" do
      assert {:ok, _} = SuggestionPolicy.feedback(%{key: "event:1", reason: "not_near"})

      assert SuggestionPolicy.feedback(%{key: "event:1", reason: "ugly"}) ==
               {:error, :invalid_partner_suggestion_feedback}

      assert SuggestionPolicy.feedback(%{key: "nope", reason: "other"}) ==
               {:error, :invalid_partner_suggestion_key}
    end

    test "weights and order live in one place" do
      assert Map.keys(SuggestionPolicy.weights()) |> Enum.sort() ==
               [:booked_both, :booked_one, :fairness, :shared_time, :soon]

      assert SuggestionPolicy.order() == [:booked, :shared_time, :fairness, :starts_at, :key]
    end
  end

  # ------------------------------------------------------------ properties

  defp candidate_gen do
    gen all(
          n <- integer(1..40),
          kind <- member_of(~w(class event trial)),
          offset <- integer(-86_400..(9 * 86_400)),
          capacity <- one_of([constant(nil), integer(0..3)]),
          cancelled <- boolean(),
          lat_off <- float(min: -0.2, max: 0.2),
          lng_off <- float(min: -0.2, max: 0.2),
          has_point <- frequency([{4, constant(true)}, {1, constant(false)}]),
          level <- member_of([nil, "beginner", "all_levels", "advanced"]),
          booked <- member_of([[], [@me], [@other], [@me, @other], ["stranger"]]),
          organiser <- member_of([nil, "org-1", "org-2", "org-3"]),
          zone <- member_of([@athens, "Etc/UTC", nil])
        ) do
      {lat, lng} = @centre

      %{
        kind: kind,
        id: "c#{n}",
        title: "t",
        starts_at: DateTime.add(@now, offset, :second),
        ends_at: nil,
        time_zone: zone,
        point: if(has_point, do: {lat + lat_off, lng + lng_off}),
        level: level,
        capacity_left: capacity,
        cancelled: cancelled,
        organiser_id: organiser,
        booked_by: booked,
        place: nil
      }
    end
  end

  # Any subset of `values`, in their order.
  defp subset_of(values) do
    map(list_of(boolean(), length: length(values)), fn flags ->
      for {true, value} <- Enum.zip(flags, values), do: value
    end)
  end

  defp person_gen(id) do
    gen all(
          times <- subset_of(SuggestionPolicy.slots()),
          level <- member_of([nil, "beginner", "intermediate", "advanced"]),
          max_km <- member_of([2, 5, 10, 25])
        ) do
      %{id: id, times: times, level: level, max_km: max_km, point: @centre}
    end
  end

  defp input_gen do
    gen all(
          candidates <- list_of(candidate_gen(), max_length: 25),
          me <- person_gen(@me),
          other <- person_gen(@other),
          blocked <- subset_of(["org-1", "org-2", "org-3"])
        ) do
      %{
        people: [me, other],
        candidates: Enum.uniq_by(candidates, & &1.id),
        blocked_ids: blocked,
        now: @now
      }
    end
  end

  property "never full, cancelled, past, out of window, out of range or blocked; at most 3" do
    check all(input <- input_gen()) do
      result = SuggestionPolicy.suggest(input)
      [me, other] = input.people
      limit = DateTime.add(@now, 7 * 86_400, :second)

      assert length(result) <= 3

      for s <- result do
        refute s.cancelled
        assert DateTime.compare(s.starts_at, @now) == :gt
        assert DateTime.compare(s.starts_at, limit) != :gt
        assert is_nil(s.capacity_left) or s.capacity_left > 0 or length(s.booked_by) == 2
        refute s.organiser_id in input.blocked_ids
        assert Enum.all?(s.booked_by, &(&1 in [@me, @other]))

        case s.distances_km do
          [nil, _] -> assert s.kind == "class"
          [_, nil] -> assert s.kind == "class"
          [a, b] -> assert a <= me.max_km + 0.05 and b <= other.max_km + 0.05
        end
      end
    end
  end

  property "the order is deterministic and ignores input order" do
    check all(input <- input_gen(), seed <- integer()) do
      :rand.seed(:exsss, {seed, seed, seed})
      shuffled = %{input | candidates: Enum.shuffle(input.candidates)}

      assert SuggestionPolicy.suggest(shuffled) == SuggestionPolicy.suggest(input)
      assert SuggestionPolicy.suggest(input) == SuggestionPolicy.suggest(input)
    end
  end

  property "booked activities come before unbooked ones" do
    check all(input <- input_gen()) do
      booked = Enum.map(SuggestionPolicy.suggest(input), &length(&1.booked_by))
      assert booked == Enum.sort(booked, :desc)
    end
  end
end
