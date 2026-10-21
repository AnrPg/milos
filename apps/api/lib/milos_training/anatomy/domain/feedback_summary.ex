defmodule MilosTraining.Anatomy.Domain.FeedbackSummary do
  @moduledoc """
  Coach totals of «τι ένιωσες» feedback on a workout or a class (ADR-163,
  board 18 Q6). Pure.

  - Shown only with at least three entries, so nobody is singled out; below
    that the lists are empty and `shown` is false (`entries` still counts).
  - Muscles roll up to their group (`MuscleTaxonomy.group_of/1`); each entry
    counts a group or a quality once.
  - Lists are ordered by count, then taxonomy (or quality) order.
  - `goals_not_felt`: the groups of the goal's primary and secondary muscles
    nobody felt, in goal order. Stabilizers are left out: members are not
    shown them on the card and are not expected to feel them.
  """

  alias MilosTraining.Anatomy.Domain.{FitnessQualities, MuscleTaxonomy}

  @min_entries 3

  def min_entries, do: @min_entries

  @doc """
  `rows` are `%{felt_muscles, felt_qualities}`, one per entry; `goal_muscles`
  the `[%{id, role}]` of the goals in force (or `[]`).
  """
  def summarize(rows, goal_muscles) when is_list(rows) do
    entries = length(rows)

    if entries < @min_entries do
      %{entries: entries, shown: false, felt_muscles: [], felt_qualities: [], goals_not_felt: []}
    else
      muscle_counts = count(rows, &felt_groups/1)
      quality_counts = count(rows, &Enum.uniq(&1.felt_qualities || []))

      %{
        entries: entries,
        shown: true,
        felt_muscles: ranked(muscle_counts, group_order()),
        felt_qualities: ranked(quality_counts, quality_order()),
        goals_not_felt: goals_not_felt(goal_muscles || [], muscle_counts)
      }
    end
  end

  defp felt_groups(row) do
    (row.felt_muscles || [])
    |> Enum.map(&MuscleTaxonomy.group_of/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp count(rows, ids_of) do
    rows
    |> Enum.flat_map(ids_of)
    |> Enum.frequencies()
  end

  defp ranked(counts, order) do
    counts
    |> Enum.sort_by(fn {id, n} -> {-n, Map.get(order, id, map_size(order))} end)
    |> Enum.map(fn {id, n} -> %{id: id, count: n} end)
  end

  defp goals_not_felt(goal_muscles, muscle_counts) do
    goal_muscles
    |> Enum.filter(&(to_string(&1.role) in ["primary", "secondary"]))
    |> Enum.map(&MuscleTaxonomy.group_of(&1.id))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.reject(&Map.has_key?(muscle_counts, &1))
  end

  defp group_order,
    do: MuscleTaxonomy.groups() |> Enum.with_index() |> Map.new(fn {g, i} -> {g.id, i} end)

  defp quality_order, do: FitnessQualities.all() |> Enum.with_index() |> Map.new()
end
