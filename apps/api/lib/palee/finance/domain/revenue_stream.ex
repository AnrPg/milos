defmodule Palee.Finance.Domain.RevenueStream do
  @moduledoc """
  The revenue streams Finance separates (ADR-190), pure.

    * `membership` - package subscriptions, renewals and their adjustments
      (every row that existed before ADR-190);
    * `package` - reserved for PT/service packs sold apart from memberships;
    * `event` - event and season charges;
    * `shop` - the e-shop (online orders and desk sales);
    * `other` - manual charges of any other category.

  The stream is a column on invoices, invoice lines, payments and
  reversals, set by the writer (or by the database for reversals and manual
  charges), never derived from text.
  """

  @keys ~w(membership package event shop other)

  @spec keys() :: [String.t()]
  def keys, do: @keys

  @doc "A stream key from a request value, or an error."
  @spec parse(term()) :: {:ok, String.t()} | {:error, :invalid_revenue_stream}
  def parse(value) when is_atom(value) and not is_nil(value), do: parse(Atom.to_string(value))
  def parse(value) when value in @keys, do: {:ok, value}
  def parse(_value), do: {:error, :invalid_revenue_stream}

  @doc """
  The per-stream totals of a period from payment and reversal rows
  (`%{revenue_stream, currency, cents}`): paid, refunded and net per stream
  and currency, every stream present (zero when it had nothing).
  """
  @spec totals([map()], [map()]) :: [map()]
  def totals(payments, reversals) do
    paid = sum_by(payments)
    refunded = sum_by(reversals)
    currencies = (Map.keys(paid) ++ Map.keys(refunded)) |> Enum.map(&elem(&1, 1)) |> Enum.uniq()
    currencies = if currencies == [], do: ["EUR"], else: Enum.sort(currencies)

    for currency <- currencies, stream <- @keys do
      paid_cents = Map.get(paid, {stream, currency}, 0)
      refunded_cents = Map.get(refunded, {stream, currency}, 0)

      %{
        revenue_stream: stream,
        currency: currency,
        paid_cents: paid_cents,
        refunded_cents: refunded_cents,
        net_cents: paid_cents - refunded_cents
      }
    end
  end

  defp sum_by(rows) do
    Enum.reduce(rows, %{}, fn row, acc ->
      Map.update(acc, {row.revenue_stream, row.currency}, row.cents, &(&1 + row.cents))
    end)
  end
end
