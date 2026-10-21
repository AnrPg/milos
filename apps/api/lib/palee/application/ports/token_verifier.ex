defmodule Palee.Application.Ports.TokenVerifier do
  alias Palee.Identity.Account

  @callback decode_refresh_token(String.t() | nil) :: {:ok, map()} | {:error, term()}
  @callback user_from_claims(map()) :: {:ok, Account.t()} | {:error, term()}
end
