defmodule MilosTraining.Anatomy.Domain.GoalSuggestion do
  @moduledoc """
  Deterministic WOD-goal suggestion from a workout's exercises (ADR-163, D3).

  Input is a list of `%{exercise_ref, weight}` (weight = how much of the
  workout the exercise is, e.g. its set count; defaults to 1). Each exercise
  contributes its curated targets (`ExerciseTargets`):

    * a muscle's goal role is the strongest role any exercise gives it, but a
      muscle that only stabilizes keeps the role only when it stabilizes a
      meaningful share of the workout, so a long WOD does not list the whole
      body as stabilizers;
    * a head is dropped when its group is already a goal with an equal or
      stronger role (the group already says it);
    * qualities are ranked by the weight of the exercises that develop them
      and the strongest ones are kept.

  The coach edits the result; nothing here is ever shown without that chance.
  """

  alias MilosTraining.Anatomy.Domain.{ExerciseTargets, FitnessQualities, MuscleTaxonomy}

  @max_stabilizers 6
  @max_qualities 5
  @stabilizer_share 0.25
  @quality_share 0.2

  def suggest(exercises) when is_list(exercises) do
    resolved =
      exercises
      |> Enum.map(fn exercise ->
        {ExerciseTargets.fetch(field(exercise, :exercise_ref)), weight(exercise)}
      end)
      |> Enum.reject(fn {targets, _weight} -> is_nil(targets) end)

    total = resolved |> Enum.map(&elem(&1, 1)) |> Enum.sum()

    %{
      muscles: muscles(resolved, total),
      qualities: qualities(resolved, total),
      matched_exercises: length(resolved),
      unmatched_exercises: length(exercises) - length(resolved)
    }
  end

  defp muscles(_resolved, total) when total <= 0, do: []

  defp muscles(resolved, total) do
    scores =
      Enum.reduce(resolved, %{}, fn {%{muscles: muscles}, weight}, acc ->
        Enum.reduce(muscles, acc, fn %{id: id, role: role}, acc ->
          Map.update(
            acc,
            id,
            %{role: role, weight: weight, by_role: %{role => weight}},
            fn entry ->
              %{
                role: stronger(entry.role, role),
                weight: entry.weight + weight,
                by_role: Map.update(entry.by_role, role, weight, &(&1 + weight))
              }
            end
          )
        end)
      end)

    {stabilizers, movers} =
      scores
      |> Enum.split_with(fn {_id, entry} -> entry.role == :stabilizer end)

    kept_stabilizers =
      stabilizers
      |> Enum.filter(fn {_id, entry} -> entry.weight / total >= @stabilizer_share end)
      |> Enum.sort_by(fn {id, entry} -> {-entry.weight, order(id)} end)
      |> Enum.take(@max_stabilizers)

    goals = Map.new(movers ++ kept_stabilizers, fn {id, entry} -> {id, entry.role} end)

    goals
    |> Enum.reject(fn {id, role} -> covered_by_group?(id, role, goals) end)
    |> Enum.map(fn {id, role} -> %{id: id, role: role} end)
    |> Enum.sort_by(fn %{id: id, role: role} -> {-ExerciseTargets.role_rank(role), order(id)} end)
  end

  defp covered_by_group?(id, role, goals) do
    case MuscleTaxonomy.fetch(id) do
      %{kind: :head, group_id: group_id} ->
        case Map.fetch(goals, group_id) do
          {:ok, group_role} ->
            ExerciseTargets.role_rank(group_role) >= ExerciseTargets.role_rank(role)

          :error ->
            false
        end

      _other ->
        false
    end
  end

  defp qualities(_resolved, total) when total <= 0, do: []

  defp qualities(resolved, total) do
    resolved
    |> Enum.flat_map(fn {%{qualities: qualities}, weight} ->
      Enum.map(qualities, &{&1, weight})
    end)
    |> Enum.reduce(%{}, fn {id, weight}, acc -> Map.update(acc, id, weight, &(&1 + weight)) end)
    |> Enum.filter(fn {_id, weight} -> weight / total >= @quality_share end)
    |> Enum.sort_by(fn {id, weight} ->
      {-weight, Enum.find_index(FitnessQualities.all(), &(&1 == id))}
    end)
    |> Enum.take(@max_qualities)
    |> Enum.map(&elem(&1, 0))
  end

  defp stronger(a, b),
    do: if(ExerciseTargets.role_rank(a) >= ExerciseTargets.role_rank(b), do: a, else: b)

  @order MuscleTaxonomy.nodes() |> Enum.with_index() |> Map.new(fn {n, i} -> {n.id, i} end)
  defp order(id), do: Map.get(@order, id, 10_000)

  defp weight(exercise) do
    case field(exercise, :weight) do
      w when is_number(w) and w > 0 -> w
      _other -> 1
    end
  end

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
