defmodule Palee.Application.Ports.TokenIssuer do
  alias Palee.Identity.Account

  @callback issue_pair(Account.t()) ::
              {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, term()}
end
