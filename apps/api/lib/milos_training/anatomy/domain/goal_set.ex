defmodule MilosTraining.Anatomy.Domain.GoalSet do
  @moduledoc """
  Validation and normalisation of a goal set (ADR-163): the muscles a coach
  names for a workout and the muscles and qualities an athlete says they felt.

  A goal set is `%{muscles: [%{id, role}], qualities: [id], stimulus: text}`.
  Muscles must be targetable taxonomy nodes (groups or heads); roles are
  `primary | secondary | stabilizer` for goals. Feedback uses the same muscle
  ids without roles.
  """

  alias MilosTraining.Anatomy.Domain.{ExerciseTargets, FitnessQualities, MuscleTaxonomy}

  @max_muscles 40
  @max_stimulus 280
  @roles ~w(primary secondary stabilizer)

  @doc "Normalises coach-authored goals or returns `{:error, {:invalid_goals, details}}`."
  def normalize_goals(params) when is_map(params) do
    with {:ok, muscles} <- goal_muscles(field(params, :muscles) || []),
         {:ok, qualities} <- qualities(field(params, :qualities) || []),
         {:ok, stimulus} <- stimulus(field(params, :stimulus)) do
      {:ok, %{muscles: muscles, qualities: qualities, stimulus: stimulus}}
    end
  end

  def normalize_goals(_params), do: {:error, {:invalid_goals, %{goals: "must be an object"}}}

  @doc "Normalises athlete feedback: felt muscle ids (no roles) and felt qualities."
  def normalize_feedback(params) when is_map(params) do
    with {:ok, muscles} <- felt_muscles(field(params, :felt_muscles) || []),
         {:ok, qualities} <- qualities(field(params, :felt_qualities) || []) do
      {:ok, %{felt_muscles: muscles, felt_qualities: qualities}}
    end
  end

  def normalize_feedback(_params),
    do: {:error, {:invalid_goals, %{feedback: "must be an object"}}}

  defp goal_muscles(list) when is_list(list) and length(list) <= @max_muscles do
    list
    |> Enum.reduce_while({:ok, %{}}, fn item, {:ok, acc} ->
      id = field(item, :id)
      role = to_string(field(item, :role) || "")

      cond do
        not MuscleTaxonomy.targetable?(id) ->
          {:halt, {:error, {:invalid_goals, %{muscles: "unknown muscle #{inspect(id)}"}}}}

        role not in @roles ->
          {:halt, {:error, {:invalid_goals, %{muscles: "invalid role #{inspect(role)}"}}}}

        true ->
          role = String.to_existing_atom(role)
          {:cont, {:ok, Map.update(acc, id, role, &stronger(&1, role))}}
      end
    end)
    |> case do
      {:ok, by_id} ->
        {:ok,
         by_id
         |> Enum.map(fn {id, role} -> %{id: id, role: role} end)
         |> Enum.sort_by(fn %{id: id, role: role} ->
           {-ExerciseTargets.role_rank(role), order(id)}
         end)}

      error ->
        error
    end
  end

  defp goal_muscles(_list),
    do: {:error, {:invalid_goals, %{muscles: "must be a list of at most #{@max_muscles}"}}}

  defp felt_muscles(list) when is_list(list) and length(list) <= @max_muscles do
    ids = Enum.map(list, &if(is_map(&1), do: field(&1, :id), else: &1))

    case Enum.reject(ids, &MuscleTaxonomy.targetable?/1) do
      [] ->
        {:ok, ids |> Enum.uniq() |> Enum.sort_by(&order/1)}

      [bad | _rest] ->
        {:error, {:invalid_goals, %{felt_muscles: "unknown muscle #{inspect(bad)}"}}}
    end
  end

  defp felt_muscles(_list),
    do: {:error, {:invalid_goals, %{felt_muscles: "must be a list of at most #{@max_muscles}"}}}

  defp qualities(list) when is_list(list) do
    case Enum.reject(list, &FitnessQualities.known?/1) do
      [] -> {:ok, FitnessQualities.normalize(list)}
      [bad | _rest] -> {:error, {:invalid_goals, %{qualities: "unknown quality #{inspect(bad)}"}}}
    end
  end

  defp qualities(_list), do: {:error, {:invalid_goals, %{qualities: "must be a list"}}}

  defp stimulus(nil), do: {:ok, nil}

  defp stimulus(text) when is_binary(text) do
    case String.trim(text) do
      "" -> {:ok, nil}
      trimmed when byte_size(trimmed) > @max_stimulus * 4 -> too_long()
      trimmed -> if String.length(trimmed) > @max_stimulus, do: too_long(), else: {:ok, trimmed}
    end
  end

  defp stimulus(_text), do: {:error, {:invalid_goals, %{stimulus: "must be text"}}}

  defp too_long,
    do: {:error, {:invalid_goals, %{stimulus: "must be at most #{@max_stimulus} characters"}}}

  defp stronger(a, b),
    do: if(ExerciseTargets.role_rank(a) >= ExerciseTargets.role_rank(b), do: a, else: b)

  @order MuscleTaxonomy.nodes() |> Enum.with_index() |> Map.new(fn {n, i} -> {n.id, i} end)
  defp order(id), do: Map.get(@order, id, 10_000)

  defp field(map, key) when is_map(map), do: Map.get(map, key) || Map.get(map, to_string(key))
  defp field(_map, _key), do: nil
end
