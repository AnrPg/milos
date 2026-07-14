defmodule MilosTraining.Application.Ports.TokenStore do
  @callback revoke(String.t(), non_neg_integer()) :: :ok | {:error, term()}
  @callback revoked?(String.t()) :: {:ok, boolean()} | {:error, term()}
  @callback consume(String.t(), non_neg_integer()) :: {:ok, boolean()} | {:error, term()}
end
