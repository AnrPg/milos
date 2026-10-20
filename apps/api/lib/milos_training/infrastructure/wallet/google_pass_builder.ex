defmodule MilosTraining.Infrastructure.Wallet.GooglePassBuilder do
  @moduledoc """
  Google adapter of `Wallet.Ports.PassBuilder` (ADR-155): the «Save to Google
  Wallet» link, a JWT (RS256, signed with the issuer's service-account key)
  carrying the generic class and the member's generic object.
  """

  @behaviour MilosTraining.Wallet.Ports.PassBuilder

  alias MilosTraining.Infrastructure.Wallet.Credentials
  alias MilosTraining.Wallet.Domain.GooglePass

  @impl true
  def configured?, do: match?({:ok, _credentials}, Credentials.google())

  @impl true
  def build(content, opts) do
    with {:ok, credentials} <- Credentials.google() do
      claims =
        GooglePass.save_claims(
          content,
          %{
            issuer_id: credentials.issuer_id,
            service_account_email: credentials.service_account_email,
            origins: credentials.origins,
            logo_url: Map.get(opts, :logo_url)
          },
          Map.get(opts, :now) || DateTime.utc_now()
        )

      {:ok, %{kind: :save_link, url: GooglePass.save_url(sign(claims, credentials))}}
    end
  end

  @doc false
  def sign(claims, credentials) do
    jwk = JOSE.JWK.from_pem(credentials.private_key_pem)
    {_header, jwt} = jwk |> JOSE.JWT.sign(%{"alg" => "RS256"}, claims) |> JOSE.JWS.compact()
    jwt
  end
end
