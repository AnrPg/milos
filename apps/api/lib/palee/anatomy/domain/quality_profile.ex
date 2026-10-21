defmodule Palee.Anatomy.Domain.QualityProfile do
  @moduledoc """
  The qualities radar (ADR-165): how much of the athlete's training developed
  each of the ten fitness qualities (`FitnessQualities`), and how often they
  felt each one. Pure.

  Each set of a recognised exercise counts once for every quality the
  exercise develops (`ExerciseTargets`; unknown set count = 1, as in
  coverage). `score` is the quality's share of the most-trained quality
  (0..1, two decimals), so the radar shows a shape, not a grade. `felt`
  counts the entries where the athlete ticked the quality. Every quality is
  always listed, in canonical order, so the radar keeps its axes.
  """

  alias Palee.Anatomy.Domain.{ExerciseTargets, FitnessQualities}

  @doc """
  `%{sessions, qualities: [%{id, sets, score, felt}]}` from performances
  (`%{exercises: [%{exercise_ref, sets}]}`) and felt rows
  (`%{felt_qualities: [id]}`).
  """
  def build(performances, felt) when is_list(performances) and is_list(felt) do
    sets =
      performances
      |> Enum.flat_map(&List.wrap(Map.get(&1, :exercises)))
      |> Enum.reduce(%{}, fn exercise, acc ->
        exercise
        |> Map.get(:exercise_ref)
        |> qualities()
        |> Enum.reduce(
          acc,
          &Map.update(&2, &1, sets(exercise), fn total -> total + sets(exercise) end)
        )
      end)

    felt_counts =
      felt
      |> Enum.flat_map(&(&1 |> Map.get(:felt_qualities) |> List.wrap() |> Enum.uniq()))
      |> Enum.frequencies()

    top = sets |> Map.values() |> Enum.max(fn -> 0 end)

    %{
      sessions: Enum.count(performances, &trained?/1),
      qualities:
        Enum.map(FitnessQualities.all(), fn id ->
          total = Map.get(sets, id, 0)

          %{
            id: id,
            sets: total,
            score: if(top > 0, do: Float.round(total / top, 2), else: 0.0),
            felt: Map.get(felt_counts, id, 0)
          }
        end)
    }
  end

  defp trained?(performance) do
    performance
    |> Map.get(:exercises)
    |> List.wrap()
    |> Enum.any?(&(qualities(&1.exercise_ref) != []))
  end

  defp qualities(ref) do
    case ExerciseTargets.fetch(ref) do
      %{qualities: qualities} -> qualities
      nil -> []
    end
  end

  defp sets(%{sets: sets}) when is_integer(sets) and sets > 0, do: sets
  defp sets(_exercise), do: 1
end
