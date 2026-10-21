defmodule MilosTraining.Devices.Domain.Pkce do
  @moduledoc """
  OAuth 2.0 PKCE (RFC 7636) as Garmin's authorization server requires it:
  a high-entropy verifier kept server-side, its S256 challenge sent with the
  sign-in, and the `state` that ties the return to the sign-in, stored only
  as a hash. Randomness is the caller's (pass the bytes in).
  """

  @doc "A verifier from at least 32 random bytes (43+ URL-safe characters)."
  def verifier(random) when is_binary(random) and byte_size(random) >= 32,
    do: Base.url_encode64(random, padding: false)

  @doc "`BASE64URL(SHA256(verifier))`."
  def challenge(verifier) when is_binary(verifier),
    do: :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)

  def challenge_method, do: "S256"

  @doc "A `state` value from random bytes."
  def state(random) when is_binary(random) and byte_size(random) >= 16,
    do: Base.url_encode64(random, padding: false)

  @doc "What is stored and looked up for a `state`."
  def state_hash(state) when is_binary(state),
    do: :sha256 |> :crypto.hash(state) |> Base.encode16(case: :lower)

  @doc "A verifier is 43–128 characters of the unreserved set (RFC 7636 §4.1)."
  def valid_verifier?(verifier) when is_binary(verifier),
    do: String.match?(verifier, ~r/\A[A-Za-z0-9\-._~]{43,128}\z/)

  def valid_verifier?(_verifier), do: false
end
