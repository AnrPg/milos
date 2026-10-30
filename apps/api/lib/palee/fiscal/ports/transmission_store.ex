defmodule Palee.Fiscal.Ports.TransmissionStore do
  @moduledoc """
  Persistence of authority connections and the transmission outbox
  (ADR-243). Every callback takes the tenant context first.

  Claiming moves due rows to `sending` and spends one attempt in a single
  statement (`FOR UPDATE SKIP LOCKED`), so two workers never send the same
  document at once; `finish/4` records the attempt and the new state in
  one transaction.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  # Connections
  @doc "The connection with its decrypted credentials, or nil."
  @callback get_connection(context(), authority :: String.t()) :: map() | nil
  @callback save_connection(context(), authority :: String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback set_connection_status(context(), String.t(), String.t(), String.t() | nil) :: :ok
  @doc "Records a connection check (ADR-273); see `EInvoiceStore.update_connection_check/3`."
  @callback update_connection_check(context(), String.t(), map()) :: :ok

  # Transmissions
  @callback insert_transmission(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_transmission(context(), id()) :: map() | nil
  @callback transmissions_for_documents(context(), [id()]) :: %{id() => map()}
  @doc "Claims due rows (or the one with `id`) and returns them."
  @callback claim(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback finish(context(), id(), map(), map() | nil) :: {:ok, map()} | {:error, term()}
  @callback update_transmission(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Makes every waiting row due now (after a connection is fixed)."
  @callback wake_waiting(context(), DateTime.t()) :: non_neg_integer()
  @callback list_transmissions(context(), map()) :: %{
              transmissions: [map()],
              total: non_neg_integer(),
              counts: %{String.t() => non_neg_integer()}
            }
  @callback list_attempts(context(), id()) :: [map()]
end
