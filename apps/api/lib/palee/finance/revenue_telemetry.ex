defmodule Palee.Finance.RevenueTelemetry do
  @moduledoc """
  The `:telemetry` events of money in and out, per revenue stream (ADR-192
  §5). Every writer of a paid payment or a refund emits one, whichever
  store it goes through (Finance's own commands, ADR-190's stream store):

    * `[:palee, :finance, :revenue, :recorded]` - `%{amount_cents, count: 1}`
    * `[:palee, :finance, :revenue, :refunded]` - `%{amount_cents, count: 1}`

  Metadata is `%{stream, currency}` only: both are closed lists, so the
  Prometheus labels stay bounded. Business ids never become labels; the
  per-business figures are the reports.
  """

  @streams ~w(membership package event shop other)

  @doc "A paid payment of `amount_cents` in `stream`."
  def payment_recorded(stream, amount_cents, currency \\ "EUR"),
    do: emit(:recorded, stream, amount_cents, currency)

  @doc "A refund (reversal) of `amount_cents` in `stream`."
  def refund_recorded(stream, amount_cents, currency \\ "EUR"),
    do: emit(:refunded, stream, amount_cents, currency)

  @doc "Emits for a `{:ok, payment}` result when the payment is paid; passes the result through."
  def observe_payment({:ok, %{} = payment} = result) do
    if Map.get(payment, :payment_status, "paid") == "paid",
      do: payment_recorded(stream_of(payment), Map.get(payment, :amount_cents), currency(payment))

    result
  end

  def observe_payment(result), do: result

  @doc "Emits for a `{:ok, reversal}` result; passes the result through."
  def observe_reversal({:ok, %{} = reversal} = result) do
    refund_recorded(stream_of(reversal), Map.get(reversal, :amount_cents), currency(reversal))
    result
  end

  def observe_reversal(result), do: result

  defp emit(kind, stream, amount_cents, currency) when is_integer(amount_cents) do
    :telemetry.execute(
      [:palee, :finance, :revenue, kind],
      %{amount_cents: amount_cents, count: 1},
      %{stream: bounded_stream(stream), currency: bounded_currency(currency)}
    )
  end

  defp emit(_kind, _stream, _amount_cents, _currency), do: :ok

  defp stream_of(row), do: Map.get(row, :revenue_stream) || "membership"
  defp currency(row), do: Map.get(row, :currency) || "EUR"

  defp bounded_stream(stream) when stream in @streams, do: stream

  defp bounded_stream(stream) when is_atom(stream) and not is_nil(stream),
    do: bounded_stream(Atom.to_string(stream))

  defp bounded_stream(_stream), do: "other"

  # ISO 4217 codes are three letters; anything else is folded so a bad value
  # cannot mint label values.
  defp bounded_currency(<<_::binary-size(3)>> = code) do
    if code =~ ~r/^[A-Z]{3}$/, do: code, else: "XXX"
  end

  defp bounded_currency(_currency), do: "XXX"
end
