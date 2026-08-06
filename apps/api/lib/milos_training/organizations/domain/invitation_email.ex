defmodule MilosTraining.Organizations.Domain.InvitationEmail do
  @moduledoc """
  Normalization and digesting for invitation email binding (F-10).

  Issuing and redemption must agree byte-for-byte on how an address is
  normalized or the comparison silently never matches — which is how the
  original `intended_email_digest` gap went unnoticed. Both sides go through
  here.
  """

  @doc "Downcases and trims an address so casing/whitespace never decide a match."
  def normalize(email) when is_binary(email) do
    email |> String.trim() |> String.downcase()
  end

  def normalize(_email), do: nil

  @doc """
  Digest of an address, or nil for a blank/absent one so callers can express
  "this invitation is not bound to an address".
  """
  def digest(nil), do: nil

  def digest(email) when is_binary(email) do
    case normalize(email) do
      "" -> nil
      normalized -> :crypto.hash(:sha256, normalized)
    end
  end

  def digest(_email), do: nil

  @doc """
  Whether `email` satisfies `expected_digest`.

  A nil digest means the invitation was issued without binding it to an
  address, so anyone holding the token may redeem it — the pre-existing
  behaviour, preserved deliberately.
  """
  def matches?(nil = _expected_digest, _email), do: true

  def matches?(expected_digest, email) when is_binary(expected_digest) do
    case digest(email) do
      nil -> false
      actual -> :crypto.hash_equals(expected_digest, actual)
    end
  end
end
