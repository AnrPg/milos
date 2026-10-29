defmodule Palee.Payments.Ports.Fulfilment do
  @moduledoc """
  What a succeeded payment pays for (ADR-246): the application layer
  records the money where its purpose lives (Finance invoice, package,
  shop order, booking) and issues the fiscal document. Called again until
  it succeeds, so it must be idempotent per intent.
  """

  @callback fulfil(context :: map(), intent :: map()) ::
              {:ok, map()} | {:error, term()}

  @doc "Records money given back for a fulfilled intent (idempotent per refund)."
  @callback reverse(context :: map(), intent :: map(), refund :: map()) ::
              {:ok, map()} | {:error, term()}
end
