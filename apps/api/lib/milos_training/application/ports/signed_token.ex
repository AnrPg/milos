defmodule MilosTraining.Application.Ports.SignedToken do
  @callback sign(String.t(), map()) :: String.t()
  @callback verify(String.t(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
end
