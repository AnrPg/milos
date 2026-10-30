defmodule Palee.Fiscal.Ports.EInvoiceStore do
  @moduledoc """
  Persistence of e-invoicing network connections and the submission
  outbox (ADR-250). Every callback takes the tenant context first.

  Claiming moves due `pending` rows to `sending` and spends one attempt,
  and leases due `submitted` rows for a delivery poll, in statements that
  lock with `FOR UPDATE SKIP LOCKED`, so two workers never handle the same
  submission at once; `finish/4` records the attempt and the new state in
  one transaction. A `sending` row whose worker died may have reached the
  access point: it becomes `uncertain` and is never sent again by itself.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @doc "The connection with its decrypted credentials, or nil."
  @callback get_connection(context(), network :: String.t()) :: map() | nil
  @callback save_connection(context(), network :: String.t(), map()) ::
              {:ok, map()} | {:error, term()}
  @callback set_connection_status(context(), String.t(), String.t(), String.t() | nil) :: :ok
  @doc """
  Records a connection check (ADR-273): any of `status`, `last_error`,
  `error_code`, `checked_at`, `next_check_at`, `check_failures`. Leaves
  `updated_at` alone (it says when the connection was saved).
  """
  @callback update_connection_check(context(), String.t(), map()) :: :ok

  @callback insert_submission(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_submission(context(), id()) :: map() | nil
  @callback submissions_for_documents(context(), [id()]) :: %{id() => map()}
  @doc "Claims due rows (or the one with `id`) and returns them."
  @callback claim(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback finish(context(), id(), map(), map() | nil) :: {:ok, map()} | {:error, term()}
  @callback update_submission(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Makes every waiting row due now (after a connection is fixed)."
  @callback wake_waiting(context(), DateTime.t()) :: non_neg_integer()
  @doc "Makes the delivery poll of the submission with this provider id due now."
  @callback wake_submitted(context(), String.t(), DateTime.t()) :: non_neg_integer()
  @callback list_submissions(context(), map()) :: %{
              submissions: [map()],
              total: non_neg_integer(),
              counts: %{String.t() => non_neg_integer()}
            }
  @callback list_attempts(context(), id()) :: [map()]
end
