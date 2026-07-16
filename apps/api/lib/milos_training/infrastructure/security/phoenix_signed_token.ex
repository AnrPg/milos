defmodule MilosTraining.Infrastructure.Security.PhoenixSignedToken do
  @behaviour MilosTraining.Application.Ports.SignedToken

  @impl true
  def sign(salt, payload), do: Phoenix.Token.sign(MilosTrainingWeb.Endpoint, salt, payload)

  @impl true
  def verify(salt, token, options),
    do: Phoenix.Token.verify(MilosTrainingWeb.Endpoint, salt, token, options)
end
