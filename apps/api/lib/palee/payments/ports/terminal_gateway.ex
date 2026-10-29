defmodule Palee.Payments.Ports.TerminalGateway do
  @moduledoc """
  A provider's card-terminal app on the staff phone (ADR-249): the request
  the phone hands to the app (Viva: `vivapayclient://pay/v1?…`), and the
  provider's own word about the transaction the app reports.

  `account` is the business's provider account with decoded `credentials`
  (as in `Payments.Ports.Gateway`). Errors are the gateway's errors.
  """

  alias Palee.Payments.Ports.Gateway

  @type sale :: %{
          reference: String.t(),
          amount_cents: pos_integer(),
          currency: String.t(),
          description: String.t(),
          app_id: String.t(),
          callback: String.t()
        }

  @type app_request :: %{
          scheme: String.t(),
          params: %{optional(String.t()) => String.t()}
        }

  @typedoc """
  A transaction as the provider reports it: the gateway's `payment`, plus
  the merchant reference it was taken with and when it was created, when
  the provider tells.
  """
  @type transaction :: %{
          required(:status) => :succeeded | :pending | :failed | :cancelled,
          required(:transaction_id) => String.t() | nil,
          optional(:amount_cents) => integer() | nil,
          optional(:currency) => String.t() | nil,
          optional(:reference) => String.t() | nil,
          optional(:created_at) => DateTime.t() | nil,
          optional(:card) => Gateway.card() | nil,
          optional(:failure) => %{code: String.t(), message: String.t() | nil} | nil
        }

  @doc "The sale request the phone hands to the provider's terminal app."
  @callback app_request(Gateway.account(), sale()) :: app_request()

  @doc "What the provider says about a transaction the terminal app reported."
  @callback confirm(Gateway.account(), transaction_id :: String.t()) ::
              {:ok, transaction()} | {:error, Gateway.error()}

  @doc """
  Looks for a transaction taken with `reference` on `date` (the business's
  local day), for a request whose result never came back.
  """
  @callback find_by_reference(Gateway.account(), reference :: String.t(), Date.t()) ::
              {:ok, transaction() | nil} | {:error, Gateway.error()}
end
