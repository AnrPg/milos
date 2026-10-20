defmodule MilosTraining.Application.Ports.EventPayments do
  @moduledoc """
  Where a payment for a place on a paid club event is recorded (ADR-153).
  There are no online payments: people pay at the box and staff press
  «Πλήρωσε». The adapter writes the money where the box keeps it and says
  which documents it made (nil ids when it kept none).

  Called inside the event's lock: an error rolls the payment back.
  """

  @type payment :: %{
          user_id: binary(),
          amount_cents: non_neg_integer(),
          currency: String.t(),
          method: String.t(),
          description: String.t(),
          recorded_by_id: binary(),
          reference: String.t()
        }

  @callback record(context :: map(), payment()) ::
              {:ok, %{finance_invoice_id: binary() | nil, finance_payment_id: binary() | nil}}
              | {:error, term()}
end
