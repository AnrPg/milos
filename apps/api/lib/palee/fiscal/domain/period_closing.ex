defmodule Palee.Fiscal.Domain.PeriodClosing do
  @moduledoc """
  Daily, monthly and yearly closings of the fiscal journal (ADR-242).

  A closing sums the documents issued in the period (by gym-local issue
  date), per currency: how many of each kind, signed net, tax and gross
  (credit notes count negative), tax per rate, and the perpetual grand
  totals carried from the previous closing of the same kind: the signed
  grand total and the grand total in absolute value, as NF525 asks.

  Days close once they have ended in the gym's time zone. A month closes
  after its last day, a year after its last month. Closing is idempotent:
  the store refuses a second closing of the same period.
  """

  @kinds ~w(day month year)

  def kinds, do: @kinds

  @doc "First and last date of the period of `kind` that contains `date`."
  def bounds("day", %Date{} = date), do: {date, date}

  def bounds("month", %Date{} = date),
    do: {Date.beginning_of_month(date), Date.end_of_month(date)}

  def bounds("year", %Date{year: year}), do: {Date.new!(year, 1, 1), Date.new!(year, 12, 31)}

  @doc """
  Periods that must be closed now, oldest first, as `{kind, first, last}`.

    * `today` – the gym-local date now (only earlier days close);
    * `first_activity` – the issue date of the first document, or nil;
    * `last_closed` – `%{"day" => date, "month" => date, "year" => date}`
      with the last day of the latest closing of each kind (missing when
      none yet).

  `limit` caps the number of days returned so a long gap closes over
  several runs.
  """
  def due(today, first_activity, last_closed, limit \\ 400)

  def due(_today, nil, _last_closed, _limit), do: []

  def due(%Date{} = today, %Date{} = first_activity, last_closed, limit) do
    yesterday = Date.add(today, -1)

    days =
      case Map.get(last_closed, "day") do
        nil -> first_activity
        last -> Date.add(last, 1)
      end
      |> dates_until(yesterday)
      |> Enum.take(limit)

    last_day_closed = List.last(days) || Map.get(last_closed, "day")

    months = coarser("month", first_activity, Map.get(last_closed, "month"), last_day_closed)
    years = coarser("year", first_activity, Map.get(last_closed, "year"), last_day_closed)

    Enum.map(days, &{"day", &1, &1}) ++ months ++ years
  end

  defp dates_until(from, to) do
    if Date.compare(from, to) == :gt, do: [], else: Date.range(from, to) |> Enum.to_list()
  end

  # Months (or years) whose last day is closed and that are not closed yet.
  defp coarser(_kind, _first, _last_closed, nil), do: []

  defp coarser(kind, first_activity, last_closed, last_day_closed) do
    start =
      case last_closed do
        nil -> elem(bounds(kind, first_activity), 0)
        last -> Date.add(last, 1)
      end

    start
    |> Stream.unfold(fn from ->
      {first, last} = bounds(kind, from)
      {{kind, first, last}, Date.add(last, 1)}
    end)
    |> Enum.take_while(fn {_kind, _first, last} -> Date.compare(last, last_day_closed) != :gt end)
  end

  @doc """
  Totals of `documents` (maps with `kind`, `currency`, `net_cents`,
  `tax_cents`, `gross_cents` and `tax_breakdown` rows `%{rate_bp, net_cents,
  tax_cents}`), carrying the grand totals of `previous` (the previous
  closing's totals, or `%{}`).
  """
  def totals(documents, previous_totals) do
    current =
      Enum.reduce(documents, %{}, fn document, acc ->
        sign = if document.kind == "credit_note", do: -1, else: 1

        Map.update(acc, document.currency, add(empty(), document, sign), &add(&1, document, sign))
      end)

    currencies = Enum.uniq(Map.keys(current) ++ Map.keys(previous_totals))

    Map.new(currencies, fn currency ->
      period = Map.get(current, currency, empty())
      previous = Map.get(previous_totals, currency, %{})

      {currency,
       Map.merge(period, %{
         "grand_total_cents" => Map.get(previous, "grand_total_cents", 0) + period["gross_cents"],
         "grand_total_absolute_cents" =>
           Map.get(previous, "grand_total_absolute_cents", 0) + period["absolute_gross_cents"]
       })}
    end)
  end

  defp empty do
    %{
      "documents" => 0,
      "receipts" => 0,
      "invoices" => 0,
      "credit_notes" => 0,
      "net_cents" => 0,
      "tax_cents" => 0,
      "gross_cents" => 0,
      "absolute_gross_cents" => 0,
      "by_rate" => %{}
    }
  end

  defp add(totals, document, sign) do
    kind_key =
      case document.kind do
        "receipt" -> "receipts"
        "invoice" -> "invoices"
        "credit_note" -> "credit_notes"
      end

    by_rate =
      Enum.reduce(document.tax_breakdown || [], totals["by_rate"], fn row, acc ->
        rate = row |> value(:rate_bp) |> Integer.to_string()

        Map.update(
          acc,
          rate,
          %{
            "net_cents" => sign * value(row, :net_cents),
            "tax_cents" => sign * value(row, :tax_cents)
          },
          fn existing ->
            %{
              "net_cents" => existing["net_cents"] + sign * value(row, :net_cents),
              "tax_cents" => existing["tax_cents"] + sign * value(row, :tax_cents)
            }
          end
        )
      end)

    %{
      totals
      | "documents" => totals["documents"] + 1,
        kind_key => totals[kind_key] + 1,
        "net_cents" => totals["net_cents"] + sign * document.net_cents,
        "tax_cents" => totals["tax_cents"] + sign * document.tax_cents,
        "gross_cents" => totals["gross_cents"] + sign * document.gross_cents,
        "absolute_gross_cents" => totals["absolute_gross_cents"] + document.gross_cents,
        "by_rate" => by_rate
    }
  end

  # Breakdown rows come back from the database with string keys.
  defp value(row, key), do: Map.get(row, key) || Map.get(row, Atom.to_string(key)) || 0
end
