defmodule MilosTraining.Application.Ports.TokenVerifier do
  alias MilosTraining.Identity.Account

  @callback decode_refresh_token(String.t() | nil) :: {:ok, map()} | {:error, term()}
  @callback user_from_claims(map()) :: {:ok, Account.t()} | {:error, term()}
end
