defmodule MilosTraining.Gamification.Domain.PRDetector do
  @lower_is_better ~w(time for_time duration)a

  def is_pr?(new_score, history_scores, opts \\ []) do
    score_type = normalize_score_type(new_score, opts)
    comparator = if score_type in @lower_is_better, do: &</2, else: &>/2

    with {:ok, new_value} <- numeric_value(new_score[:value] || new_score["value"], score_type) do
      relevant_history =
        history_scores
        |> Enum.filter(&same_section?(&1, new_score))
        |> Enum.map(&numeric_value(&1[:value] || &1["value"], score_type))
        |> Enum.filter(&match?({:ok, _}, &1))
        |> Enum.map(fn {:ok, value} -> value end)

      relevant_history == [] or Enum.all?(relevant_history, &comparator.(new_value, &1))
    else
      :error -> false
    end
  end

  def detect(current_scores, history_scores) do
    Enum.filter(current_scores, &is_pr?(&1, history_scores))
  end

  defp same_section?(existing, candidate) do
    (existing[:section_id] || existing["section_id"]) ==
      (candidate[:section_id] || candidate["section_id"])
  end

  defp normalize_score_type(score, opts) do
    score[:score_type] ||
      score["score_type"] ||
      opts[:score_type] ||
      opts["score_type"] ||
      :reps
  end

  defp numeric_value(value, _score_type) when is_number(value), do: {:ok, value}

  defp numeric_value(value, score_type) when is_binary(value) do
    trimmed = String.trim(value)

    cond do
      trimmed == "" ->
        :error

      score_type in @lower_is_better ->
        parse_time_or_number(trimmed)

      score_type in [:load, :weight] ->
        parse_number_with_unit(trimmed)

      score_type in [:"rounds+reps", :rounds_reps] ->
        parse_rounds_and_reps(trimmed)

      true ->
        parse_number_with_unit(trimmed)
    end
  end

  defp numeric_value(_value, _score_type), do: :error

  defp parse_time_or_number(value) do
    case String.split(value, ":") do
      [minutes, seconds] ->
        with {:ok, minute_value} <- parse_integer(minutes),
             {:ok, second_value} <- parse_integer(seconds) do
          {:ok, minute_value * 60 + second_value}
        end

      [hours, minutes, seconds] ->
        with {:ok, hour_value} <- parse_integer(hours),
             {:ok, minute_value} <- parse_integer(minutes),
             {:ok, second_value} <- parse_integer(seconds) do
          {:ok, hour_value * 3600 + minute_value * 60 + second_value}
        end

      _parts ->
        parse_number_with_unit(value)
    end
  end

  defp parse_rounds_and_reps(value) do
    case Regex.run(~r/^\s*(\d+)\D+(\d+)\s*$/u, value) do
      [_, rounds, reps] ->
        with {:ok, round_value} <- parse_integer(rounds),
             {:ok, rep_value} <- parse_integer(reps) do
          {:ok, round_value * 1_000_000 + rep_value}
        end

      _ ->
        parse_number_with_unit(value)
    end
  end

  defp parse_number_with_unit(value) do
    case Regex.run(~r/^\s*(-?\d+(?:\.\d+)?)/, value) do
      [_, numeric] -> parse_float(numeric)
      _ -> :error
    end
  end

  defp parse_integer(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end

  defp parse_float(value) do
    case Float.parse(String.trim(value)) do
      {parsed, ""} -> {:ok, parsed}
      _ -> :error
    end
  end
end
