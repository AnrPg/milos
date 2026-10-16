defmodule MilosTraining.Gamification.Domain.PerseveranceCalculator do
  @moduledoc """
  Calculates perseverance score from the member's recorded changes (the
  structured `change` of their comments, ADR-140 §1, with `logged_at` set to
  when it was written) over the last 7 training days.

  For each change: a skipped exercise deviates fully (1.0); a numeric
  change deviates by |prescribed - actual| / prescribed, capped at 1.

  Perseverance = mean(1 - deviation_ratio) per day, then mean across last 7 training days.
  Returns 100.0 when no modifications exist (no deviations = perfect execution).
  """

  @training_days_lookback 7

  @type modification :: %{
          optional(:exercise_id) => String.t(),
          optional(:field) => String.t(),
          optional(:prescribed_value) => number(),
          optional(:actual_value) => number() | nil,
          optional(:skipped) => boolean(),
          optional(:logged_at) => String.t() | DateTime.t()
        }

  @spec calculate([modification()], [integer()], Date.t()) :: float()
  def calculate(exercise_modifications, off_days, current_date)

  def calculate([], _off_days, _current_date), do: 100.0

  def calculate(exercise_modifications, off_days, %Date{} = current_date) do
    off_day_set = MapSet.new(off_days)

    recent_training_days =
      last_n_training_days(current_date, @training_days_lookback, off_day_set)

    recent_training_day_set = MapSet.new(recent_training_days)

    relevant_mods =
      Enum.filter(exercise_modifications, fn mod ->
        date = extract_date(mod)
        date && MapSet.member?(recent_training_day_set, date)
      end)

    if Enum.empty?(relevant_mods) do
      100.0
    else
      by_day = Enum.group_by(relevant_mods, &extract_date/1)

      daily_scores =
        Enum.map(by_day, fn {_date, mods} ->
          deviations = Enum.map(mods, &deviation_ratio/1)
          mean(Enum.map(deviations, &(1.0 - &1)))
        end)

      Float.round(mean(daily_scores) * 100.0, 1)
    end
  end

  defp last_n_training_days(current_date, n, off_day_set) do
    Stream.iterate(current_date, &Date.add(&1, -1))
    |> Stream.reject(fn date ->
      day_of_week = Date.day_of_week(date, :sunday) - 1
      MapSet.member?(off_day_set, day_of_week)
    end)
    |> Enum.take(n)
  end

  # A skipped exercise is a full deviation; a changed value deviates by its
  # relative distance from the prescription (`canonical_value`, or the older
  # `prescribed_value`), capped at 1. Non-numeric changes (a substitution, a
  # tempo) carry no measurable deviation.
  defp deviation_ratio(%{"type" => "skipped"}), do: 1.0
  defp deviation_ratio(%{"skipped" => true}), do: 1.0

  defp deviation_ratio(mod) do
    prescribed = number(mod, "canonical_value") || number(mod, "prescribed_value")
    actual = number(mod, "actual_value")

    if is_nil(prescribed) or is_nil(actual) or prescribed == 0.0 do
      0.0
    else
      min(abs(prescribed - actual) / abs(prescribed), 1.0)
    end
  end

  defp number(mod, key) do
    case Map.get(mod, key) do
      value when is_number(value) ->
        value / 1.0

      value when is_binary(value) ->
        case Float.parse(String.trim(value)) do
          {number, _unit} -> number
          :error -> nil
        end

      _other ->
        nil
    end
  end

  defp extract_date(%{"logged_at" => logged_at}) when is_binary(logged_at) do
    case DateTime.from_iso8601(logged_at) do
      {:ok, dt, _} -> DateTime.to_date(dt)
      _ -> nil
    end
  end

  defp extract_date(%{"logged_at" => %DateTime{} = dt}), do: DateTime.to_date(dt)
  defp extract_date(_), do: nil

  defp mean([]), do: 1.0
  defp mean(list), do: Enum.sum(list) / length(list)
end
