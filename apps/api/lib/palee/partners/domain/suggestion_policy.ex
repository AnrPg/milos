defmodule Palee.Partners.Domain.SuggestionPolicy do
  @moduledoc """
  «Κλείστε μαζί» suggestions for a Partners match (ADR-280 §4). Pure and
  deterministic: the same people, candidates, blocked ids and `now` always
  give the same suggestions in the same order, whatever the input order.

  **People** (two, the viewer first): `%{id, times, level, max_km, point}`,
  `max_km` defaulting to 10 and `point` the neighbourhood centroid
  `{latitude, longitude}` or nil.

  **Candidates**: `%{kind, id, title, starts_at, ends_at, time_zone, point
  | distances_km, level | levels, capacity_left, cancelled, organiser_id,
  booked_by, place}`. `kind` is `class` (a class of a box both belong to),
  `event` or `trial`; `capacity_left` nil means no limit; `booked_by` holds
  which of the two people booked it, never anyone else.

  **Hard filters**: not cancelled, not started, starting within
  7 days; free places left (a full activity stays only when both are
  already in); within each person's distance from their own neighbourhood
  (an unknown distance passes only for a shared box's class); the level
  fits both; neither blocked the organiser.

  **Order** (`order/0`): booked by either → how many time slots both chose
  the start falls in (in the activity's own zone) → fairness (the smaller
  maximum of the two distances) → sooner start → kind and id. At most
  3. The tiers and their weights live in `weights/0`, so tuning is one
  change here.

  Each suggestion carries its `reasons` (`both_booked`, `one_booked`,
  `shared_time:<slot>`, `level_fit`, `near_both`) and `distances_km`
  `[viewer, other]` to one decimal. It never says who else attends.
  """

  @window_days 7
  @max 3
  @default_km 10
  @kinds ~w(class event trial)
  @slots ~w(early midday afternoon evening weekend)
  @person_levels ~w(beginner intermediate advanced)
  @earth_radius_km 6371.0088

  # A class level (Scheduling vocabulary) admits these Partners levels.
  @class_levels %{
    "beginner" => ~w(beginner intermediate),
    "all_levels" => @person_levels,
    "intermediate" => @person_levels,
    "advanced" => ~w(intermediate advanced)
  }

  @order [:booked, :shared_time, :fairness, :starts_at, :key]

  @reason_keys ~w(both_booked one_booked shared_time level_fit near_both)
  @feedback_reasons ~w(not_near bad_time wrong_level other)
  @events ~w(shown proposed booked_together feedback)

  @doc """
  The ordering tiers, applied lexicographically in `order/0`'s order. Each
  weight scales its tier's value; a weight of 0 switches a tier off.

  * `booked_both` / `booked_one`: the value of being booked by both / one.
  * `shared_time`: per time slot both chose that the start falls in.
  * `fairness`: per kilometre of the farther person's distance (lower first).
  * `soon`: per second until the start (sooner first).
  """
  def weights,
    do: %{booked_both: 2, booked_one: 1, shared_time: 1, fairness: 1, soon: 1}

  def order, do: @order
  def reason_keys, do: @reason_keys
  def feedback_reasons, do: @feedback_reasons
  def events, do: @events

  @doc "Checks a «Δεν ταιριάζει» answer: `{:ok, %{key, reason}}` or an error."
  def feedback(%{key: key, reason: reason}) do
    cond do
      parse_key(key) == :error -> {:error, :invalid_partner_suggestion_key}
      reason not in @feedback_reasons -> {:error, :invalid_partner_suggestion_feedback}
      true -> {:ok, %{key: key, reason: reason}}
    end
  end

  def feedback(_params), do: {:error, :invalid_partner_suggestion_feedback}
  def kinds, do: @kinds
  def slots, do: @slots
  def class_levels, do: @class_levels
  def window_days, do: @window_days
  def max_suggestions, do: @max
  def default_km, do: @default_km

  @doc "The window candidates are gathered in: `{now, now + 7 days}`."
  def window(%DateTime{} = now), do: {now, DateTime.add(now, @window_days * 86_400, :second)}

  @doc "A suggestion's stable key, what feedback and plans name: `kind:id`."
  def key(%{kind: kind, id: id}), do: "#{kind}:#{id}"

  @doc "Parses a key back into `{kind, id}`, or `:error`."
  def parse_key(key) when is_binary(key) do
    case String.split(key, ":", parts: 2) do
      [kind, id] when kind in @kinds and byte_size(id) in 1..64 -> {:ok, {kind, id}}
      _other -> :error
    end
  end

  def parse_key(_key), do: :error

  @doc """
  Ranked suggestions for `%{people: [viewer, other], candidates, blocked_ids,
  now}`: at most 3 maps of the candidate's fields plus `key`, `booked_by`,
  `distances_km` and `reasons`.
  """
  def suggest(
        %{people: [_a, _b] = people, candidates: candidates, now: %DateTime{} = now} = input
      ) do
    people = Enum.map(people, &person/1)
    blocked = MapSet.new(Map.get(input, :blocked_ids, []))
    pair = Enum.map(people, & &1.id)

    # Sorted first so a duplicated key keeps the same entry in any input order.
    candidates
    |> Enum.sort_by(&{key(&1), &1})
    |> Enum.uniq_by(&key/1)
    |> Enum.map(&evaluate(&1, people, pair))
    |> Enum.filter(&eligible?(&1, people, blocked, now))
    |> Enum.sort_by(&rank/1)
    |> Enum.take(@max)
    |> Enum.map(&present/1)
  end

  @doc """
  The time slots a start falls in, in `time_zone`: one of `early` (before
  9), `midday` (9–15), `afternoon` (15–18) or `evening`, plus `weekend` on
  Saturday and Sunday.
  """
  def slots_of(%DateTime{} = at, time_zone) do
    local = local(at, time_zone)

    hour =
      cond do
        local.hour < 9 -> "early"
        local.hour < 15 -> "midday"
        local.hour < 18 -> "afternoon"
        true -> "evening"
      end

    if Date.day_of_week(local) in [6, 7], do: [hour, "weekend"], else: [hour]
  end

  @doc "Whether an activity's level (or accepted levels) fits a person's level."
  def level_fits?(_activity_levels, nil), do: true
  def level_fits?(nil, _person_level), do: true
  def level_fits?(levels, level) when is_list(levels), do: level in levels

  @doc "Great-circle distance in km between two `{latitude, longitude}` points."
  def distance_km({lat1, lng1}, {lat2, lng2})
      when is_number(lat1) and is_number(lng1) and is_number(lat2) and is_number(lng2) do
    dlat = radians(lat2 - lat1)
    dlng = radians(lng2 - lng1)

    h =
      :math.pow(:math.sin(dlat / 2), 2) +
        :math.cos(radians(lat1)) * :math.cos(radians(lat2)) * :math.pow(:math.sin(dlng / 2), 2)

    2 * @earth_radius_km * :math.asin(min(1.0, :math.sqrt(h)))
  end

  def distance_km(_a, _b), do: nil

  # ------------------------------------------------------------ internals

  defp person(person) do
    %{
      id: Map.fetch!(person, :id),
      times: Map.get(person, :times) || [],
      level: Map.get(person, :level),
      max_km: Map.get(person, :max_km) || @default_km,
      point: Map.get(person, :point)
    }
  end

  defp evaluate(candidate, [a, b] = people, pair) do
    booked_by =
      candidate
      |> Map.get(:booked_by, [])
      |> Enum.filter(&(&1 in pair))
      |> Enum.uniq()
      |> Enum.sort_by(&Enum.find_index(pair, fn id -> id == &1 end))

    shared =
      candidate.starts_at
      |> slots_of(Map.get(candidate, :time_zone))
      |> Enum.filter(&(&1 in a.times and &1 in b.times))

    %{
      candidate: candidate,
      key: key(candidate),
      booked_by: booked_by,
      shared: shared,
      distances: distances(candidate, people),
      levels: levels(candidate)
    }
  end

  defp distances(%{distances_km: [da, db]}, _people), do: [da, db]

  defp distances(candidate, people),
    do: Enum.map(people, &distance_km(&1.point, Map.get(candidate, :point)))

  defp levels(%{levels: levels}) when is_list(levels), do: levels
  defp levels(%{level: level}) when is_binary(level), do: Map.get(@class_levels, level, [level])
  defp levels(_candidate), do: nil

  defp eligible?(item, [a, b], blocked, now) do
    candidate = item.candidate

    Map.get(candidate, :kind) in @kinds and
      not Map.get(candidate, :cancelled, false) and
      DateTime.compare(candidate.starts_at, now) == :gt and
      DateTime.compare(candidate.starts_at, elem(window(now), 1)) != :gt and
      has_room?(candidate, item.booked_by) and
      within?(candidate.kind, Enum.at(item.distances, 0), a.max_km) and
      within?(candidate.kind, Enum.at(item.distances, 1), b.max_km) and
      level_fits?(item.levels, a.level) and level_fits?(item.levels, b.level) and
      not MapSet.member?(blocked, Map.get(candidate, :organiser_id))
  end

  defp has_room?(candidate, booked_by) do
    case Map.get(candidate, :capacity_left) do
      nil -> true
      left when is_integer(left) and left > 0 -> true
      _full -> length(booked_by) == 2
    end
  end

  defp within?("class", nil, _max_km), do: true
  defp within?(_kind, nil, _max_km), do: false
  defp within?(_kind, distance, max_km), do: distance <= max_km

  # Lexicographic, lowest first; ties end at the key, so the order is total.
  defp rank(item) do
    w = weights()

    booked =
      case length(item.booked_by) do
        2 -> w.booked_both
        1 -> w.booked_one
        0 -> 0
      end

    {
      -booked,
      -length(item.shared) * w.shared_time,
      fairness(item.distances) * w.fairness,
      DateTime.to_unix(item.candidate.starts_at, :microsecond) * w.soon,
      item.key
    }
  end

  # The farther of the two, in metres so the comparison is exact; unknown last.
  defp fairness(distances) do
    if Enum.any?(distances, &is_nil/1),
      do: 1_000_000_000,
      else: distances |> Enum.max() |> Kernel.*(1000) |> round()
  end

  defp present(item) do
    item.candidate
    |> Map.drop([:point, :distances_km, :booked_by])
    |> Map.merge(%{
      key: item.key,
      booked_by: item.booked_by,
      distances_km: Enum.map(item.distances, &round_km/1),
      reasons: reasons(item)
    })
  end

  defp reasons(item) do
    booked =
      case length(item.booked_by) do
        2 -> ["both_booked"]
        1 -> ["one_booked"]
        0 -> []
      end

    level = if item.levels, do: ["level_fit"], else: []
    near = if Enum.all?(item.distances, &is_number/1), do: ["near_both"], else: []

    booked ++ Enum.map(item.shared, &"shared_time:#{&1}") ++ level ++ near
  end

  defp round_km(nil), do: nil
  defp round_km(km), do: Float.round(km * 1.0, 1)

  defp local(at, nil), do: at

  defp local(at, time_zone) do
    case DateTime.shift_zone(at, time_zone) do
      {:ok, local} -> local
      _error -> at
    end
  end

  defp radians(degrees), do: degrees * :math.pi() / 180
end
