defmodule MilosTraining.Application.SignedToken do
  @behaviour MilosTraining.Application.Ports.SignedToken

  @impl true
  def sign(salt, payload), do: impl().sign(salt, payload)
  @impl true
  def verify(salt, token, options \\ []), do: impl().verify(salt, token, options)

  defp impl, do: Application.fetch_env!(:milos_training, :signed_token)
end
