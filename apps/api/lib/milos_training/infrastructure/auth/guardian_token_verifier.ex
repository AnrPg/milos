defmodule MilosTraining.Infrastructure.Auth.GuardianTokenVerifier do
  @behaviour MilosTraining.Application.Ports.TokenVerifier

  alias MilosTraining.Infrastructure.Auth.Guardian

  @impl true
  def decode_refresh_token(refresh_token) do
    Guardian.decode_and_verify(refresh_token, %{"typ" => "refresh"})
  end

  @impl true
  def user_from_claims(claims) do
    Guardian.resource_from_claims(claims)
  end
end
