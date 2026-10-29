defmodule Palee.Fiscal.Ports.TillSignatureStore do
  @moduledoc """
  Persistence of till connections and the receipt signature outbox
  (ADR-251). Every callback takes the tenant context first.

  Claiming moves due `pending` and `uncertain` rows to `sending` (keeping
  whether the next call is a sign or a read-back) and spends one attempt,
  locking with `FOR UPDATE SKIP LOCKED`; `finish/4` records the attempt
  and the new state in one transaction.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @doc "The connection with its decrypted credentials, or nil."
  @callback get_connection(context(), device :: String.t()) :: map() | nil
  @callback save_connection(context(), device :: String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback set_connection_status(context(), String.t(), String.t(), String.t() | nil) :: :ok

  @callback insert_signature(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_signature(context(), id()) :: map() | nil
  @callback signatures_for_documents(context(), [id()]) :: %{id() => map()}
  @doc "Claims due rows (or the one with `id`); each keeps `claimed_from` (its status before)."
  @callback claim(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback finish(context(), id(), map(), map() | nil) :: {:ok, map()} | {:error, term()}
  @callback update_signature(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback wake_waiting(context(), DateTime.t()) :: non_neg_integer()
  @callback list_signatures(context(), map()) :: %{
              signatures: [map()],
              total: non_neg_integer(),
              counts: %{String.t() => non_neg_integer()}
            }
  @callback list_attempts(context(), id()) :: [map()]
end
