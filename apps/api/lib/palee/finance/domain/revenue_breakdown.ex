defmodule Palee.Finance.Domain.RevenueBreakdown do
  @moduledoc """
  Paid revenue split by revenue stream (ADR-192 §1-2), pure.

  ADR-190 puts a `revenue_stream` column on payments, invoice lines and
  reversals (`membership | package | event | shop | other`, the list of
  `Palee.Finance.Domain.RevenueStream`). Every row older than it, and every
  writer that names no stream, holds the column default `membership`, so the
  column alone cannot tell a monthly membership from a class pack or an
  event ticket. The breakdown reads the column first and refines only its
  default:

    1. a stream other than the default, set by its writer (the shop writes
       `shop`), is taken as is;
    2. a default-stream payment for a package subscription is `membership`
       for recurring package types and `package` for one-off ones (class
       packs, drop-ins, trials, PT packs, add-ons);
    3. a default-stream event ticket receipt (ADR-153), or a payment of an
       invoice with an `event` line, is `event`;
    4. any other default-stream payment (a manual receipt) is `other`.

  Nothing is back-filled: the refinement happens when a report is read, so
  no stored figure is rewritten. Refunds belong to the stream of the
  payment they reverse.
  """

  @streams ~w(membership package event shop other)
  # ADR-190's column default: what every older row holds.
  @default_stream "membership"
  @recurring_package_types ~w(membership shared corporate)
  @one_off_package_types ~w(class_pack drop_in trial pt_pack add_on)
  @event_reference_prefix "community_event_attendee:"

  @type stream :: String.t()

  @typedoc """
  What the classifier looks at. Every key is optional:

    * `:explicit_stream` - the payment's `revenue_stream` column;
    * `:package_type` - the package type of the paid subscription;
    * `:reference` - the receipt's idempotency key or source reference;
    * `:charge_category` - the category of a manual invoice line.
  """
  @type fact :: %{
          optional(:explicit_stream) => String.t() | nil,
          optional(:package_type) => String.t() | nil,
          optional(:reference) => String.t() | nil,
          optional(:charge_category) => String.t() | nil
        }

  @doc "Every stream, in display order."
  @spec all() :: [stream()]
  def all, do: @streams

  @doc "True for a known stream name."
  @spec valid?(term()) :: boolean()
  def valid?(stream), do: stream in @streams

  @doc "The stream of one payment fact."
  @spec classify(fact()) :: stream()
  def classify(fact) when is_map(fact) do
    explicit = Map.get(fact, :explicit_stream)
    package_type = Map.get(fact, :package_type)

    cond do
      explicit in @streams and explicit != @default_stream -> explicit
      package_type in @recurring_package_types -> "membership"
      package_type in @one_off_package_types -> "package"
      is_binary(package_type) -> "membership"
      event?(fact) -> "event"
      true -> "other"
    end
  end

  defp event?(fact) do
    Map.get(fact, :charge_category) == "event" or
      String.starts_with?(Map.get(fact, :reference) || "", @event_reference_prefix)
  end

  @doc "A zero for every stream."
  @spec zeros() :: %{stream() => 0}
  def zeros, do: Map.new(@streams, &{&1, 0})

  @doc """
  Folds `{fact, gross_cents, net_cents, payment_count}` groups into one row
  per stream (every stream present, in display order) and the net per
  stream. The nets add up to the sum of the groups' nets, so a breakdown
  built from the same groups as a headline figure always adds up to it.
  """
  @spec breakdown([{fact(), integer(), integer(), non_neg_integer()}]) ::
          %{rows: [map()], net_by_stream: %{stream() => integer()}}
  def breakdown(groups) when is_list(groups) do
    empty = Map.new(@streams, &{&1, %{gross_cents: 0, net_cents: 0, payment_count: 0}})

    totals =
      Enum.reduce(groups, empty, fn {fact, gross, net, count}, acc ->
        Map.update!(acc, classify(fact), fn row ->
          %{
            gross_cents: row.gross_cents + gross,
            net_cents: row.net_cents + net,
            payment_count: row.payment_count + count
          }
        end)
      end)

    rows =
      Enum.map(@streams, fn stream ->
        row = Map.fetch!(totals, stream)

        %{
          stream: stream,
          gross_cents: row.gross_cents,
          refunded_cents: row.gross_cents - row.net_cents,
          net_cents: row.net_cents,
          payment_count: row.payment_count
        }
      end)

    %{rows: rows, net_by_stream: Map.new(rows, &{&1.stream, &1.net_cents})}
  end
end
