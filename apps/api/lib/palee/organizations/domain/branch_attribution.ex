defmodule Palee.Organizations.Domain.BranchAttribution do
  @moduledoc """
  The home branch of a person, so reports can be split by branch (ADR-186 §7).

  Most facts behind the finance, coaching and statistics pages have no branch
  of their own: a payment, a review, an injury, a completed workout. They are
  attributed through the person they belong to, and each person has at most
  one home branch:

    1. among the branches their packages allow (every active branch when a
       package is valid everywhere, or when they have none), the one they
       trained at most in the window (check-ins and attended classes), ties
       broken by the lowest location id so the answer is stable;
    2. with no activity there, the only branch their packages allow, when
       they allow exactly one;
    3. otherwise none: the person counts in the business totals only, which
       all-branch staff see, and never under a branch filter.

  One home per person keeps per-branch splits adding up to the total (plus
  the «χωρίς κατάστημα» remainder) instead of counting a person twice.

  Pure: no Repo, no clock.
  """

  @type location_id :: String.t()
  @type user_id :: String.t()
  @type allowed :: :all | [location_id]

  @doc """
  `activity` is a list of `{user_id, location_id, count}`; `allowed` maps a
  user to the branches their packages cover; `active_ids` are the business's
  active branches. Returns `%{user_id => location_id}` for people with a home.
  """
  def home_branches(activity, allowed, active_ids) do
    active = MapSet.new(active_ids)

    counts =
      Enum.reduce(activity, %{}, fn {user_id, location_id, count}, acc ->
        if MapSet.member?(active, location_id) and is_integer(count) and count > 0,
          do: Map.update(acc, user_id, %{location_id => count}, &Map.update(&1, location_id, count, fn c -> c + count end)),
          else: acc
      end)

    users = counts |> Map.keys() |> Enum.concat(Map.keys(allowed)) |> Enum.uniq()

    Enum.reduce(users, %{}, fn user_id, acc ->
      candidates = candidates(Map.get(allowed, user_id, :all), active)

      case home(Map.get(counts, user_id, %{}), candidates, Map.get(allowed, user_id, :all)) do
        nil -> acc
        location_id -> Map.put(acc, user_id, location_id)
      end
    end)
  end

  @doc """
  Who counts under a report filter: `nil` (no restriction) for `:all`, else
  the users whose home is one of the branches.
  """
  def users_at(_homes, :all), do: nil

  def users_at(homes, location_ids) when is_list(location_ids) do
    for {user_id, location_id} <- homes, location_id in location_ids, do: user_id
  end

  @doc "The home branch of each user, grouped: `%{location_id => [user_id]}`."
  def by_branch(homes) do
    Enum.group_by(homes, &elem(&1, 1), &elem(&1, 0))
  end

  @doc """
  Check-ins and attended classes per branch from `{user_id, location_id,
  check_ins, attended}` rows: `%{location_id => %{check_ins: n, attended: n}}`.
  """
  def activity_by_branch(rows) do
    Enum.reduce(rows, %{}, fn {_user_id, location_id, check_ins, attended}, acc ->
      Map.update(
        acc,
        location_id,
        %{check_ins: check_ins, attended: attended},
        &%{check_ins: &1.check_ins + check_ins, attended: &1.attended + attended}
      )
    end)
  end

  @doc "Rows of `{user_id, location_id, check_ins, attended}` as attribution activity."
  def activity_counts(rows),
    do: Enum.map(rows, fn {user_id, location_id, check_ins, attended} -> {user_id, location_id, check_ins + attended} end)

  @doc """
  What the per-branch splits leave out (people without a home branch), for an
  additive metric: the business total minus the branches' sum, never negative.
  """
  def remainder(total, splits) when is_number(total),
    do: max(total - Enum.sum(Enum.map(splits, &(&1 || 0))), 0)

  defp candidates(:all, active), do: active

  defp candidates(ids, active) when is_list(ids),
    do: ids |> MapSet.new() |> MapSet.intersection(active)

  defp home(counts, candidates, allowed) do
    counts
    |> Enum.filter(fn {location_id, _count} -> MapSet.member?(candidates, location_id) end)
    |> Enum.sort_by(fn {location_id, count} -> {-count, location_id} end)
    |> case do
      [{location_id, _count} | _rest] -> location_id
      [] -> only_allowed(candidates, allowed)
    end
  end

  defp only_allowed(candidates, allowed) when is_list(allowed) do
    case MapSet.to_list(candidates) do
      [only] -> only
      _none_or_many -> nil
    end
  end

  defp only_allowed(_candidates, :all), do: nil
end
