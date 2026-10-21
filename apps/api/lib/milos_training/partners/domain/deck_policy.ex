defmodule MilosTraining.Partners.Domain.DeckPolicy do
  @moduledoc """
  Who shows in a club's Partners deck and in which order (ADR-169 §3). Pure.

  A candidate is a live profile of a current member, not the viewer, not
  blocked either way, not already liked, passed in the last 30 days or
  matched. Gender preferences hold both ways; a preference other than `any`
  excludes people whose gender is unset. Filters narrow by time, level and
  goal. The order is what the two share: each common time and goal weighs 2,
  the same level 1, an adjacent level ½; ties by id, so the deck is stable.
  """

  alias MilosTraining.Partners.Domain.ProfilePolicy

  @page_size 20
  @pass_cooldown_days 30

  def page_size, do: @page_size
  def pass_cooldown_days, do: @pass_cooldown_days

  @doc "The filters of a deck request; unknown values are ignored."
  def filters(params) when is_map(params) do
    %{
      time: pick(params, "time", ProfilePolicy.times()),
      level: pick(params, "level", ProfilePolicy.levels()),
      goal: pick(params, "goal", ProfilePolicy.goals())
    }
  end

  def filters(_params), do: %{time: nil, level: nil, goal: nil}

  @doc """
  The people the viewer's swipes keep out of the deck: everyone liked, and
  everyone passed less than 30 days ago.
  """
  def swiped_ids(swipes, now) do
    cutoff = DateTime.add(now, -@pass_cooldown_days * 86_400, :second)

    swipes
    |> Enum.filter(fn swipe ->
      swipe.direction == "like" or DateTime.compare(swipe.updated_at, cutoff) == :gt
    end)
    |> MapSet.new(& &1.target_id)
  end

  @doc "Whether both people's gender preferences admit each other."
  def gender_compatible?(viewer, other),
    do:
      admits?(viewer.gender_preference, other.gender) and
        admits?(other.gender_preference, viewer.gender)

  defp admits?(preference, _gender) when preference in [nil, "any"], do: true
  defp admits?("women", gender), do: gender == "woman"
  defp admits?("men", gender), do: gender == "man"
  defp admits?(_preference, _gender), do: false

  def matches_filters?(profile, %{time: time, level: level, goal: goal}) do
    (is_nil(time) or time in profile.times) and (is_nil(level) or profile.level == level) and
      (is_nil(goal) or goal in profile.goals)
  end

  @doc "What two profiles share: times, goals, and whether the level is the same."
  def shared(viewer, other) do
    %{
      times: Enum.filter(viewer.times, &(&1 in other.times)),
      goals: Enum.filter(viewer.goals, &(&1 in other.goals)),
      same_level: viewer.level == other.level
    }
  end

  def score(viewer, other) do
    %{times: times, goals: goals} = shared(viewer, other)
    2 * length(times) + 2 * length(goals) + level_weight(viewer.level, other.level)
  end

  defp level_weight(same, same), do: 1

  defp level_weight(a, b) do
    levels = ProfilePolicy.levels()

    if abs(Enum.find_index(levels, &(&1 == a)) - Enum.find_index(levels, &(&1 == b))) == 1,
      do: 0.5,
      else: 0
  end

  @doc """
  The deck: `candidates` are live profiles of current members; `excluded`
  is a set of user ids (blocked, swiped, matched). Returns
  `[{profile, shared}]`, best fit first, at most a page.
  """
  def deck(viewer, candidates, excluded, filters) do
    candidates
    |> Enum.reject(&(&1.user_id == viewer.user_id or MapSet.member?(excluded, &1.user_id)))
    |> Enum.filter(&(ProfilePolicy.live?(&1) and gender_compatible?(viewer, &1)))
    |> Enum.filter(&matches_filters?(&1, filters))
    |> Enum.sort_by(&{-score(viewer, &1), &1.user_id})
    |> Enum.take(@page_size)
    |> Enum.map(&{&1, shared(viewer, &1)})
  end

  @doc "Whether `other` may be swiped by `viewer` right now (the deck's rules for one person)."
  def swipeable?(viewer, other, excluded) do
    other.user_id != viewer.user_id and not MapSet.member?(excluded, other.user_id) and
      ProfilePolicy.live?(other) and gender_compatible?(viewer, other)
  end

  defp pick(params, key, allowed) do
    value = Map.get(params, key) || Map.get(params, String.to_existing_atom(key))
    if value in allowed, do: value
  end
end
