defmodule MilosTraining.Execution.Domain.ScoreRanking do
  @moduledoc """
  Ranks results of one workout by its scored section (ADR-138 D6): a time
  ranks lowest first; reps, rounds, rounds+reps, load and the like rank
  highest first. Results without a readable score for that section come
  last, unranked. Each member counts once, with their best result.
  """

  @lower_is_better ~w(time accumulated_work_time)

  @doc "Whether a lower value wins for this score type."
  def lower_is_better?(score_type), do: to_string(score_type) in @lower_is_better

  @doc """
  `results` carry `:user_id`, `:section_scores` and anything else the caller
  wants kept. Returns them best first, each with `:rank` (nil when unranked)
  and `:score` (the section's raw score map or nil).
  """
  def rank(results, %{id: section_id, score_type: score_type}) do
    lower? = lower_is_better?(score_type)

    {ranked, unranked} =
      results
      |> Enum.map(fn result ->
        score = section_score(result, section_id)
        {result, score, sort_value(score, score_type)}
      end)
      |> best_per_member(lower?)
      |> Enum.split_with(fn {_result, _score, value} -> not is_nil(value) end)

    ranked =
      ranked
      |> Enum.sort_by(fn {_result, _score, value} -> value end, if(lower?, do: :asc, else: :desc))
      |> with_ranks()

    ranked ++ Enum.map(unranked, fn {result, score, _value} -> decorate(result, score, nil) end)
  end

  def rank(results, nil), do: Enum.map(results, &decorate(&1, nil, nil))

  @doc "A comparable number for a raw score value, or nil when it cannot be read."
  def sort_value(nil, _score_type), do: nil
  def sort_value(%{} = score, score_type), do: parse(value_of(score), to_string(score_type))

  defp best_per_member(rows, lower?) do
    rows
    |> Enum.group_by(fn {result, _score, _value} -> result.user_id end)
    |> Enum.map(fn {_user_id, member_rows} ->
      case Enum.reject(member_rows, fn {_r, _s, value} -> is_nil(value) end) do
        [] ->
          hd(member_rows)

        scored ->
          Enum.min_by(scored, fn {_r, _s, value} -> if(lower?, do: value, else: -value) end)
      end
    end)
  end

  # Ties share a rank (1, 2, 2, 4).
  defp with_ranks(rows) do
    rows
    |> Enum.with_index(1)
    |> Enum.map_reduce(nil, fn {{result, score, value}, position}, previous ->
      rank =
        case previous do
          {^value, previous_rank} -> previous_rank
          _other -> position
        end

      {decorate(result, score, rank), {value, rank}}
    end)
    |> elem(0)
  end

  defp decorate(result, score, rank), do: result |> Map.put(:rank, rank) |> Map.put(:score, score)

  defp section_score(result, section_id) do
    Enum.find(result.section_scores || [], fn score ->
      to_string(score["section_id"] || score[:section_id]) == to_string(section_id)
    end)
  end

  defp value_of(score), do: score["value"] || score[:value]

  defp parse(value, type) when type in @lower_is_better and is_binary(value), do: seconds(value)
  defp parse(value, type) when type in @lower_is_better and is_number(value), do: value * 1.0
  defp parse(value, "rounds+reps") when is_binary(value), do: rounds_reps(value)
  defp parse(value, _type) when is_number(value), do: value * 1.0

  defp parse(value, _type) when is_binary(value) do
    case Float.parse(String.replace(String.trim(value), ",", ".")) do
      {number, _rest} -> number
      :error -> nil
    end
  end

  defp parse(_value, _type), do: nil

  defp seconds(value) do
    parts = value |> String.trim() |> String.split(":")

    with true <- length(parts) in 1..3,
         {:ok, numbers} <- numbers(parts) do
      Enum.reduce(numbers, 0.0, fn part, total -> total * 60 + part end)
    else
      _invalid -> nil
    end
  end

  defp rounds_reps(value) do
    case value |> String.trim() |> String.split("+") do
      [rounds, reps] ->
        with {:ok, [rounds, reps]} <- numbers([rounds, reps]),
             do: rounds * 10_000 + reps,
             else: (_ -> nil)

      [rounds] ->
        with {:ok, [rounds]} <- numbers([rounds]), do: rounds * 10_000, else: (_ -> nil)

      _other ->
        nil
    end
  end

  defp numbers(parts) do
    parts
    |> Enum.reduce_while({:ok, []}, fn part, {:ok, acc} ->
      case Float.parse(String.trim(part)) do
        {number, ""} when number >= 0 -> {:cont, {:ok, [number | acc]}}
        _invalid -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end
end
