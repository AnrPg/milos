defmodule Palee.Partners.DeckPolicyPropertyTest do
  @moduledoc """
  ADR-280: the deck's invariants, for any profiles. Nobody excluded, paused,
  off or incompatible ever shows; the viewer never meets themselves; filters
  hold for every card; the order is best fit first and deterministic; a page
  is at most 20 cards; the distance is always one of the steps.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Palee.Partners.Domain.{DeckPolicy, ProfilePolicy}

  @ids Enum.map(1..30, &"user-#{String.pad_leading(Integer.to_string(&1), 2, "0")}")

  defp sublist(values, opts \\ []) do
    min = Keyword.get(opts, :min, 0)
    max = Keyword.get(opts, :max, length(values))

    # A mask over the canonical list, so the order stays canonical and no
    # value repeats; at least `min`, at most `max` values.
    keep = Keyword.get(opts, :keep, 1)

    [{keep, constant(true)}, {1, constant(false)}]
    |> frequency()
    |> list_of(length: length(values))
    |> map(fn mask ->
      picked =
        values
        |> Enum.zip(mask)
        |> Enum.filter(fn {_value, keep} -> keep end)
        |> Enum.map(&elem(&1, 0))
        |> Enum.take(max)

      if length(picked) < min, do: Enum.take(values, min), else: picked
    end)
  end

  defp profile_gen(user_id) do
    gen all(
          active <- boolean(),
          paused <- frequency([{4, constant(nil)}, {1, constant(~U[2026-11-01 00:00:00Z])}]),
          level <- member_of(ProfilePolicy.levels()),
          times <- sublist(ProfilePolicy.times(), min: 1),
          goals <- sublist(ProfilePolicy.goals(), min: 1, max: 3),
          disciplines <- sublist(~w(running yoga powerlifting rowing), max: 3),
          gender <- member_of([nil | ProfilePolicy.genders()]),
          preference <- member_of(ProfilePolicy.gender_preferences())
        ) do
      %{
        id: "p-#{user_id}",
        user_id: user_id,
        active: active,
        paused_at: paused,
        level: level,
        times: times,
        goals: goals,
        disciplines: disciplines,
        gender: gender,
        gender_preference: preference
      }
    end
  end

  defp candidates_gen do
    gen all(ids <- one_of([sublist(@ids), sublist(@ids, keep: 4)]), profiles <- fixed(ids)) do
      profiles
    end
  end

  defp fixed(ids), do: ids |> Enum.map(&profile_gen/1) |> fixed_list()

  defp filters_gen do
    gen all(
          time <- member_of([nil | ProfilePolicy.times()]),
          level <- member_of([nil | ProfilePolicy.levels()]),
          goal <- member_of([nil | ProfilePolicy.goals()]),
          discipline <- member_of([nil, "running", "yoga"]),
          within <- member_of([nil, "2", 5, "10", 25, 3, "far"])
        ) do
      %{
        "time" => time,
        "level" => level,
        "goal" => goal,
        "discipline" => discipline,
        "within_km" => within
      }
    end
  end

  property "only live, compatible, not excluded people other than the viewer show" do
    check all(
            viewer <- profile_gen("viewer"),
            candidates <- candidates_gen(),
            excluded <- sublist(@ids, max: 10),
            params <- filters_gen()
          ) do
      viewer = %{viewer | active: true, paused_at: nil}
      excluded = MapSet.new(excluded)
      filters = DeckPolicy.filters(params)
      deck = DeckPolicy.deck(viewer, [viewer | candidates], excluded, filters)

      assert length(deck) <= DeckPolicy.page_size()

      for {card, shared} <- deck do
        refute card.user_id == viewer.user_id
        refute MapSet.member?(excluded, card.user_id)
        assert ProfilePolicy.live?(card)
        assert DeckPolicy.gender_compatible?(viewer, card)
        assert DeckPolicy.gender_compatible?(card, viewer)
        assert DeckPolicy.matches_filters?(card, filters)
        assert DeckPolicy.swipeable?(viewer, card, excluded)
        assert shared == DeckPolicy.shared(viewer, card)
      end
    end
  end

  property "best fit first, ties by id, and the same input gives the same deck" do
    check all(viewer <- profile_gen("viewer"), candidates <- candidates_gen()) do
      viewer = %{viewer | active: true, paused_at: nil}
      filters = DeckPolicy.filters(%{})
      deck = DeckPolicy.deck(viewer, candidates, MapSet.new(), filters)
      keys = Enum.map(deck, fn {card, _} -> {-DeckPolicy.score(viewer, card), card.user_id} end)

      assert keys == Enum.sort(keys)
      assert deck == DeckPolicy.deck(viewer, Enum.reverse(candidates), MapSet.new(), filters)
    end
  end

  property "a full page leaves out nobody who fits better than its last card" do
    check all(viewer <- profile_gen("viewer"), candidates <- candidates_gen()) do
      viewer = %{viewer | active: true, paused_at: nil}
      deck = DeckPolicy.deck(viewer, candidates, MapSet.new(), DeckPolicy.filters(%{}))
      shown = MapSet.new(deck, fn {card, _} -> card.user_id end)

      if length(deck) == DeckPolicy.page_size() do
        {last, _} = List.last(deck)
        last_key = {-DeckPolicy.score(viewer, last), last.user_id}

        for other <- candidates,
            not MapSet.member?(shown, other.user_id),
            DeckPolicy.swipeable?(viewer, other, MapSet.new()) do
          assert {-DeckPolicy.score(viewer, other), other.user_id} > last_key
        end
      else
        eligible = Enum.filter(candidates, &DeckPolicy.swipeable?(viewer, &1, MapSet.new()))
        assert MapSet.size(shown) == length(eligible)
      end
    end
  end

  property "the distance is always one of the steps, 10 km unless a step is asked" do
    check all(params <- filters_gen()) do
      within = DeckPolicy.filters(params).within_km
      assert within in DeckPolicy.distances_km()

      case params["within_km"] do
        value when value in [2, 5, 10, 25] -> assert within == value
        "2" -> assert within == 2
        "10" -> assert within == 10
        _other -> assert within == DeckPolicy.default_within_km()
      end
    end
  end

  property "passes come back after 30 days; likes never do" do
    now = ~U[2026-11-16 10:00:00Z]

    check all(
            swipes <-
              list_of(
                gen all(
                      id <- member_of(@ids),
                      direction <- member_of(~w(like pass)),
                      days <- integer(0..60)
                    ) do
                  %{
                    target_id: id,
                    direction: direction,
                    updated_at: DateTime.add(now, -days * 86_400 - 1, :second)
                  }
                end,
                max_length: 40
              )
          ) do
      swiped = DeckPolicy.swiped_ids(swipes, now)

      for swipe <- swipes do
        recent? = DateTime.diff(now, swipe.updated_at) < DeckPolicy.pass_cooldown_days() * 86_400

        if swipe.direction == "like" or recent?,
          do: assert(MapSet.member?(swiped, swipe.target_id))
      end
    end
  end
end
