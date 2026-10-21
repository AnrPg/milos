defmodule Palee.Wellness.Domain.LocalDay do
  @moduledoc """
  The member's day (ADR-159 §2): wellness counts by the calendar day where the
  member was, not by UTC. Each entry stores the zone it was logged in and the
  local date it counts for, so travel never moves past days around.
  """

  @doc "The local date of `at` in `zone`."
  def of(%DateTime{} = at, zone) when is_binary(zone) do
    case DateTime.shift_zone(at, zone) do
      {:ok, local} -> {:ok, DateTime.to_date(local)}
      {:error, _reason} -> {:error, :unknown_time_zone}
    end
  end

  def of(_at, _zone), do: {:error, :unknown_time_zone}

  def valid_zone?(zone) when is_binary(zone), do: match?({:ok, _now}, DateTime.now(zone))
  def valid_zone?(_zone), do: false

  @doc "Every date from `from` to `to`, both included."
  def range(%Date{} = from, %Date{} = to), do: Date.range(from, to) |> Enum.to_list()

  @max_span_days 92

  @doc "Parses an inclusive `from`..`to` window of at most #{@max_span_days} days."
  def parse_window(from, to) do
    with {:ok, from} <- date(from),
         {:ok, to} <- date(to),
         :ok <- ordered(from, to) do
      {:ok, from, to}
    end
  end

  defp date(%Date{} = date), do: {:ok, date}

  defp date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> {:ok, date}
      {:error, _reason} -> {:error, :invalid_date}
    end
  end

  defp date(_value), do: {:error, :invalid_date}

  defp ordered(from, to) do
    span = Date.diff(to, from)

    cond do
      span < 0 -> {:error, :invalid_date}
      span >= @max_span_days -> {:error, :date_window_too_long}
      true -> :ok
    end
  end
end
