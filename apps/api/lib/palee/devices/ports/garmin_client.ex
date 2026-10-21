defmodule Palee.Devices.Ports.GarminClient do
  @moduledoc """
  Garmin Connect Developer Program (Health + Activity APIs), as Palee uses it
  (ADR-161):

  - OAuth 2.0 with PKCE: `authorize_url/1`, `exchange_code/1`, `refresh/1`;
    the user's Garmin id from `user_id/1`, granted permissions from
    `permissions/1`; `deregister/1` ends the link at Garmin.
  - Push model: Garmin POSTs summaries (or, in ping mode, callback URLs) to
    the push endpoint; `verify_push/1` checks a request came from Garmin for
    this app; `fetch/2` pulls a callback URL's summaries.
  - History: `request_backfill/4` asks Garmin to push one summary type for a
    window; the summaries then arrive at the push endpoint like new ones.

  Credentials come from runtime config (`GARMIN_CLIENT_ID`,
  `GARMIN_CLIENT_SECRET`); without them `configured?/0` is false and every
  call answers `{:error, :garmin_not_configured}`.
  """

  @type tokens :: %{
          access_token: String.t(),
          refresh_token: String.t() | nil,
          expires_in: non_neg_integer() | nil,
          refresh_token_expires_in: non_neg_integer() | nil,
          scopes: [String.t()]
        }
  @type error :: {:error, atom() | {atom(), term()}}

  @callback configured?() :: boolean()
  @callback redirect_uri() :: String.t() | nil
  @callback authorize_url(%{state: String.t(), challenge: String.t()}) ::
              {:ok, String.t()} | error()
  @callback exchange_code(%{code: String.t(), verifier: String.t()}) :: {:ok, tokens()} | error()
  @callback refresh(String.t()) :: {:ok, tokens()} | error()
  @callback user_id(String.t()) :: {:ok, String.t()} | error()
  @callback permissions(String.t()) :: {:ok, [String.t()]} | error()
  @callback request_backfill(String.t(), String.t(), DateTime.t(), DateTime.t()) :: :ok | error()
  @callback fetch(String.t(), String.t()) :: {:ok, [map()]} | error()
  @callback deregister(String.t()) :: :ok | error()
  @callback verify_push(%{client_id: String.t() | nil, token: String.t() | nil}) ::
              :ok | {:error, :invalid_push | :garmin_not_configured}
end
