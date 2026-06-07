defmodule MilosTraining.Application.Ports.TokenIssuer do
  alias MilosTraining.Identity.Account

  @callback issue_pair(Account.t()) ::
              {:ok, %{access_token: String.t(), refresh_token: String.t()}} | {:error, term()}
end
