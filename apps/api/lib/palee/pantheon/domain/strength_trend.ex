defmodule Palee.Pantheon.Domain.StrengthTrend do
  @moduledoc """
  «Δύναμη» (ADR-285): how much stronger the person got over the last
  `@window_days`, from their weight PRs (unit `kg`) and each PR's history.

  Each lift's estimated one-rep max (Epley, the same rule as the web's
  `pr-trend.ts`: load × (1 + reps / 30), a single is the load, past
  `@max_estimate_reps` no estimate) is compared with its best estimate before
  the window. A lift counts when it has an estimate before the window and a
  new one inside it. The score is the mean of those lifts' relative gains, so
  a heavy and a light lift weigh the same. A lift first recorded inside the
  window has nothing to compare with and is only counted in `new_lifts`.

  PRs only move up, so the score is never below zero. Nil when no lift can be
  compared: the card is hidden rather than showing a number that means
  nothing.
  """

  @window_days 56
  @max_estimate_reps 12
  @top_lifts 3

  @type point :: %{on: Date.t(), value: float()}
  @type lift :: %{name: String.t(), from_kg: float(), to_kg: float(), gain_kg: float()}
  @type t :: %{
          percent: float(),
          window_days: pos_integer(),
          lifts: [lift()],
          compared_lifts: pos_integer(),
          new_lifts: non_neg_integer()
        }

  def window_days, do: @window_days

  @doc """
  `records` are the person's PRs and `history` their PR history (each with
  `pr_record_id`); `today` is the person's own date.
  """
  @spec calculate([map()], [map()], Date.t()) :: t() | nil
  def calculate(records, history, %Date{} = today) do
    window_start = Date.add(today, -@window_days)
    history_by_record = Enum.group_by(history, &field(&1, :pr_record_id))

    lifts =
      records
      |> Enum.filter(&(field(&1, :unit) == "kg"))
      |> Enum.map(fn record ->
        points =
          history_by_record
          |> Map.get(field(record, :id), [])
          |> Enum.map(
            &point(field(&1, :score), field(&1, :beaten_on), field(&1, :supporting_metrics))
          )
          |> Kernel.++([
            point(
              field(record, :current_score),
              field(record, :beaten_on),
              field(record, :supporting_metrics)
            )
          ])
          |> Enum.reject(&is_nil/1)
          |> Enum.reject(&(Date.compare(&1.on, today) == :gt))

        {field(record, :name), compare(points, window_start)}
      end)

    compared = for {name, {:compared, from, to}} <- lifts, do: lift(name, from, to)
    new_lifts = Enum.count(lifts, fn {_name, result} -> result == :new end)

    case compared do
      [] ->
        nil

      _lifts ->
        percent =
          compared
          |> Enum.map(&(&1.gain_kg / &1.from_kg * 100.0))
          |> mean()
          |> Float.round(1)

        %{
          percent: percent,
          window_days: @window_days,
          lifts: compared |> Enum.sort_by(&{-&1.gain_kg, &1.name}) |> Enum.take(@top_lifts),
          compared_lifts: length(compared),
          new_lifts: new_lifts
        }
    end
  end

  @doc "Estimated one-rep max (Epley), rounded to 0.5 kg; nil past the reps limit."
  @spec estimated_one_rep_max(number(), number()) :: float() | nil
  def estimated_one_rep_max(load, reps \\ 1)

  def estimated_one_rep_max(load, reps)
      when is_number(load) and load > 0 and is_number(reps) and reps >= 1 and
             reps <= @max_estimate_reps do
    value = if reps == 1, do: load * 1.0, else: load * (1 + reps / 30)
    Float.round(value * 2) / 2
  end

  def estimated_one_rep_max(_load, _reps), do: nil

  defp compare(points, window_start) do
    {before, inside} = Enum.split_with(points, &(Date.compare(&1.on, window_start) == :lt))

    case {before, inside} do
      {_before, []} -> :unchanged
      {[], _inside} -> :new
      _both -> {:compared, best(before), best(points)}
    end
  end

  defp lift(name, from, to) do
    %{name: name, from_kg: from, to_kg: to, gain_kg: Float.round(max(to - from, 0.0), 1)}
  end

  defp best(points), do: points |> Enum.map(& &1.value) |> Enum.max()

  # The store hands dates over as ISO strings (`normalize_pr`), tests as dates.
  defp point(score, on, metrics) when is_binary(on) do
    case Date.from_iso8601(String.slice(on, 0, 10)) do
      {:ok, date} -> point(score, date, metrics)
      {:error, _reason} -> nil
    end
  end

  defp point(score, %Date{} = on, metrics) do
    with load when is_number(load) <- number(score),
         value when is_float(value) <- estimated_one_rep_max(load, reps(metrics)) do
      %{on: on, value: value}
    else
      _no_estimate -> nil
    end
  end

  defp point(_score, _on, _metrics), do: nil

  defp reps(metrics) when is_map(metrics) do
    case number(Map.get(metrics, "reps") || Map.get(metrics, :reps)) do
      nil -> 1
      reps -> reps
    end
  end

  defp reps(_metrics), do: 1

  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value) when is_number(value), do: value
  defp number(_value), do: nil

  defp field(map, key), do: Map.get(map, key) || Map.get(map, to_string(key))

  defp mean(values), do: Enum.sum(values) / length(values)
end
