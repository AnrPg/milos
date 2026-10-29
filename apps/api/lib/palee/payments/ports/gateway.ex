defmodule Palee.Payments.Ports.Gateway do
  @moduledoc """
  A payment provider (ADR-246): Viva, Stripe, or the sandbox. Card details
  only ever reach the provider's own page (redirect, PCI DSS SAQ A); Palee
  sees the provider's references, a reusable token, the brand and the last
  4 digits.

  `account` is the business's account with decoded `credentials` (a map
  with string keys) and `settings`.

  Errors:

    * `{:declined, code, message}` – the card or bank said no;
    * `{:unauthorized, reason}` – the account's credentials were refused;
    * `{:invalid, reason}` – the provider refused the request itself;
    * `{:transient, reason}` – network, 5xx, rate limits: safe to retry;
    * `{:uncertain, reason}` – the request may have reached the provider
      and it has no idempotency key: never resend automatically.
  """

  @type account :: %{
          required(:provider) => String.t(),
          required(:environment) => String.t(),
          required(:credentials) => map(),
          required(:settings) => map(),
          optional(any()) => any()
        }
  @type error ::
          {:declined, String.t(), String.t() | nil}
          | {:unauthorized, term()}
          | {:invalid, term()}
          | {:transient, term()}
          | {:uncertain, term()}
  @type card :: %{
          brand: String.t() | nil,
          last4: String.t() | nil,
          exp_month: integer() | nil,
          exp_year: integer() | nil
        }
  @type payment :: %{
          required(:status) => :succeeded | :pending | :failed | :cancelled,
          required(:transaction_id) => String.t() | nil,
          optional(:amount_cents) => integer() | nil,
          optional(:currency) => String.t() | nil,
          optional(:card) => card() | nil,
          optional(:method_token) => String.t() | nil,
          optional(:failure) => %{code: String.t(), message: String.t() | nil} | nil
        }
  @type checkout_request :: %{
          reference: String.t(),
          amount_cents: pos_integer(),
          currency: String.t(),
          description: String.t(),
          customer: map(),
          save_method: boolean(),
          return_url: String.t(),
          cancel_url: String.t(),
          expires_at: DateTime.t(),
          idempotency_key: String.t()
        }
  @type webhook_event :: %{
          event_id: String.t(),
          type: String.t(),
          provider_ref: String.t() | nil,
          transaction_id: String.t() | nil
        }

  @doc "Checks the account's credentials with a harmless call."
  @callback check(account()) :: :ok | {:error, error()}

  @doc "Opens a checkout on the provider's page; the payer is sent to `redirect_url`."
  @callback create_checkout(account(), checkout_request()) ::
              {:ok, %{provider_ref: String.t(), redirect_url: String.t()}} | {:error, error()}

  @doc """
  What the provider says about a checkout (`provider_ref`) or a transaction
  (`transaction_id`, when known: e.g. from the return page or a webhook).
  """
  @callback fetch_payment(account(), %{
              provider_ref: String.t() | nil,
              transaction_id: String.t() | nil
            }) :: {:ok, payment()} | {:error, error()}

  @doc "Charges a saved card without the payer (merchant-initiated)."
  @callback charge_saved(account(), token :: String.t(), %{
              reference: String.t(),
              amount_cents: pos_integer(),
              currency: String.t(),
              description: String.t(),
              idempotency_key: String.t()
            }) :: {:ok, payment()} | {:error, error()}

  @doc "Gives back part or all of a payment."
  @callback refund(account(), %{
              transaction_id: String.t(),
              amount_cents: pos_integer(),
              currency: String.t(),
              idempotency_key: String.t()
            }) ::
              {:ok, %{provider_ref: String.t() | nil, status: :succeeded | :pending}}
              | {:error, error()}

  @doc """
  Reads a webhook request: `{:ok, events}` (verified where the provider
  signs, otherwise only identifiers that we confirm by asking the
  provider), `{:reply, status, body}` for a provider's URL check, or
  `{:error, :invalid_signature | :invalid_payload}`.
  """
  @callback parse_webhook(account(), %{
              method: String.t(),
              headers: [{String.t(), String.t()}],
              body: binary(),
              now: DateTime.t()
            }) ::
              {:ok, [webhook_event()]}
              | {:reply, pos_integer(), map()}
              | {:error, :invalid_signature | :invalid_payload | error()}

  @doc "The credential keys the provider needs (secrets, never returned)."
  @callback credential_keys() :: [String.t()]
  @doc "The non-secret settings the provider needs."
  @callback setting_keys() :: [String.t()]
end
