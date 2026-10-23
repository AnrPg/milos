defmodule Palee.Shop.Ports.PaymentProvider do
  @moduledoc """
  The online card payment seam (ADR-190). Palee has no card vendor yet: the
  configured adapter (`:shop_payment_provider`) is a mock that reports
  online payment as unavailable in production and simulates success and
  failure in dev and test. A real gateway implements the same callbacks.

  Captures are idempotent: a retried `capture/2` with the same
  `idempotency_key` returns the first outcome and never charges twice.
  """

  @type availability :: %{available: boolean(), reason: atom() | nil, provider: String.t()}
  @type charge :: %{
          required(:order_id) => Ecto.UUID.t(),
          required(:amount_cents) => non_neg_integer(),
          required(:currency) => String.t(),
          required(:idempotency_key) => String.t(),
          optional(:payment_token) => String.t() | nil,
          optional(any()) => any()
        }
  @type receipt :: %{provider: String.t(), reference: String.t(), captured_at: DateTime.t()}

  @doc "Whether online payment can be offered for the business (`available: false` greys out «Πληρωμή»)."
  @callback availability(map()) :: availability()

  @type method :: %{
          method: atom(),
          channel: :pos | :online,
          available: boolean(),
          reason: atom() | nil,
          provider: String.t() | nil
        }

  @doc """
  The ways staff and members can pay: the desk methods recorded by staff
  (cash, card at the terminal, transfer, other) and the online card, each
  with whether it can be offered now.
  """
  @callback payment_methods(map()) :: [method()]

  @doc "Captures the amount of an order."
  @callback capture(map(), charge()) :: {:ok, receipt()} | {:error, atom()}

  @doc "Refunds part or all of a captured payment."
  @callback refund(map(), %{
              reference: String.t(),
              amount_cents: pos_integer(),
              idempotency_key: String.t()
            }) ::
              {:ok, %{reference: String.t()}} | {:error, atom()}
end
