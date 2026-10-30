defmodule Palee.Payments.Ports.Notifier do
  @moduledoc """
  Who hears about a declined saved-card charge (ADR-260). Called once per
  declined attempt, after the intent was saved; `final` is true when no
  retry is left. Must never fail the payment flow: an adapter logs and
  swallows its own errors.
  """

  @callback charge_declined(context :: map(), intent :: map(), %{
              final: boolean(),
              options: map()
            }) :: :ok

  @doc "Staff send the member the link to pay with another card again."
  @callback card_link(context :: map(), intent :: map(), now :: DateTime.t()) :: :ok
end
