defmodule Palee.Application.SignedToken do
  @behaviour Palee.Application.Ports.SignedToken

  @impl true
  def sign(salt, payload), do: impl().sign(salt, payload)
  @impl true
  def verify(salt, token, options \\ []), do: impl().verify(salt, token, options)

  defp impl, do: Application.fetch_env!(:palee, :signed_token)
end
