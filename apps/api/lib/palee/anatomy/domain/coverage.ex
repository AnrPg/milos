defmodule Palee.Anatomy.Domain.Coverage do
  @moduledoc """
  Muscle coverage of a set of performed workouts (ADR-164): per taxonomy node
  (region, group, head) the weighted sets, sets per week, a coverage level,
  how many entries the athlete felt it in, and the exercises that added the
  most. Pure; the weighting is `CoverageWeighting`.

  Input:

    * `performances` - one per workout done: `%{exercises: [%{exercise_ref,
      sets}]}` with `exercise_ref` a Quick Text catalog id (or `nil` when the
      exercise was not recognised) and `sets` a positive integer
    * `felt` - one per entry with feedback: `%{felt_muscles: [id]}`
    * `weeks` - the length of the range, for the per-week levels

  Only nodes with sets or felt entries are returned, in tree order; a node
  not listed has nothing.
  """

  alias Palee.Anatomy.Domain.{CoverageWeighting, MuscleTaxonomy}

  @top_exercises 3

  def build(performances, felt, weeks) when is_list(performances) and is_list(felt) do
    exercises = Enum.flat_map(performances, &List.wrap(Map.get(&1, :exercises)))
    {recognized, unrecognized} = Enum.split_with(exercises, &recognized?/1)

    by_node = sets_by_node(recognized)
    felt_by_node = felt_by_node(felt)

    nodes =
      for node <- MuscleTaxonomy.nodes(),
          contributions = Map.get(by_node, node.id, %{}),
          felt_count = Map.get(felt_by_node, node.id, 0),
          contributions != %{} or felt_count > 0 do
        sets = contributions |> Map.values() |> Enum.sum()

        %{
          id: node.id,
          kind: Atom.to_string(node.kind),
          sets: round1(sets),
          per_week: round1(sets / weeks),
          level: CoverageWeighting.level(sets, weeks),
          felt: felt_count,
          top_exercises: top_exercises(contributions)
        }
      end

    %{
      sessions: length(performances),
      exercises: %{recognized: length(recognized), unrecognized: length(unrecognized)},
      nodes: nodes
    }
  end

  defp recognized?(exercise) do
    CoverageWeighting.exercise_weights(Map.get(exercise, :exercise_ref)) != %{}
  end

  # node_id => %{exercise_ref => weighted sets}
  defp sets_by_node(exercises) do
    Enum.reduce(exercises, %{}, fn exercise, acc ->
      ref = exercise.exercise_ref
      sets = sets(exercise)

      ref
      |> CoverageWeighting.exercise_weights()
      |> Enum.reduce(acc, fn {node_id, weight}, inner ->
        Map.update(inner, node_id, %{ref => sets * weight}, fn per_exercise ->
          Map.update(per_exercise, ref, sets * weight, &(&1 + sets * weight))
        end)
      end)
    end)
  end

  defp sets(%{sets: sets}) when is_integer(sets) and sets > 0, do: sets
  defp sets(_exercise), do: 1

  defp felt_by_node(rows) do
    rows
    |> Enum.flat_map(&CoverageWeighting.felt_nodes(Map.get(&1, :felt_muscles)))
    |> Enum.frequencies()
  end

  defp top_exercises(contributions) do
    contributions
    |> Enum.sort_by(fn {ref, sets} -> {-sets, ref} end)
    |> Enum.take(@top_exercises)
    |> Enum.map(fn {ref, sets} -> %{exercise_ref: ref, sets: round1(sets)} end)
  end

  defp round1(value), do: Float.round(value * 1.0, 1)
end
