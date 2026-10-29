defmodule Palee.Payments.Ports.PaymentStore do
  @moduledoc """
  Persistence of payment accounts, intents, saved methods, refunds and
  webhook events (ADR-246/247). Every callback takes the tenant context
  first. Claims lease rows (`claimed_at`, `FOR UPDATE SKIP LOCKED`) so two
  workers never call the provider for the same intent at once.
  """

  @type context :: map()
  @type id :: Ecto.UUID.t()

  @callback transaction(context(), (-> {:ok, term()} | {:error, term()})) ::
              {:ok, term()} | {:error, term()}

  # Account
  @doc "The account with decoded credentials, or nil."
  @callback get_account(context()) :: map() | nil
  @callback get_account(context(), id()) :: map() | nil
  @callback save_account(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback set_account_status(context(), id(), String.t(), String.t() | nil, DateTime.t()) ::
              :ok

  # Intents
  @callback insert_intent(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_intent(context(), id()) :: map() | nil
  @callback get_intent_by_key(context(), String.t()) :: map() | nil
  @callback get_intent_by_ref(context(), provider :: String.t(), ref :: String.t()) :: map() | nil
  @callback update_intent(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Leases open intents that are due (or the one with `id`)."
  @callback claim_due(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @doc "Leases succeeded intents whose fulfilment is due (or the one with `id`)."
  @callback claim_fulfilments(context(), :due | id(), DateTime.t(), pos_integer()) :: [map()]
  @callback list_intents(context(), map()) :: %{intents: [map()], total: non_neg_integer()}
  @callback add_refunded(context(), id(), pos_integer()) :: {:ok, map()} | {:error, term()}

  # Saved methods
  @doc "Saves a method; the same card (token) again updates the existing row."
  @callback upsert_method(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_method(context(), id()) :: map() | nil
  @callback list_methods(context(), user_id :: id()) :: [map()]
  @callback update_method(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @doc "Turns autopay off on the user's other methods."
  @callback clear_autopay(context(), user_id :: id(), except :: id()) :: :ok
  @callback autopay_methods(context()) :: [map()]

  # Refunds
  @callback insert_refund(context(), map()) :: {:ok, map()} | {:error, term()}
  @callback get_refund_by_key(context(), String.t()) :: map() | nil
  @callback update_refund(context(), id(), map()) :: {:ok, map()} | {:error, term()}
  @callback list_refunds(context(), intent_id :: id()) :: [map()]

  # Webhooks
  @doc "`{:ok, event}` the first time, `{:duplicate, event}` after that."
  @callback record_webhook_event(context(), map()) ::
              {:ok, map()} | {:duplicate, map()} | {:error, term()}
  @callback finish_webhook_event(context(), id(), String.t(), String.t() | nil, DateTime.t()) ::
              :ok
end
