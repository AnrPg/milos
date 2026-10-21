defmodule Palee.Infrastructure.Security.PhoenixSignedToken do
  @behaviour Palee.Application.Ports.SignedToken

  @impl true
  def sign(salt, payload), do: Phoenix.Token.sign(PaleeWeb.Endpoint, salt, payload)

  @impl true
  def verify(salt, token, options),
    do: Phoenix.Token.verify(PaleeWeb.Endpoint, salt, token, options)
end
