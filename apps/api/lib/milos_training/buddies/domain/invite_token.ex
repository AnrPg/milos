defmodule MilosTraining.Buddies.Domain.InviteToken do
  @moduledoc """
  The secret of an off-platform buddy invite link (ADR-160 §1). Only its
  SHA-256 digest is stored; the link itself is shown once, to the inviter,
  who shares it themselves.
  """

  @entropy_bytes 32

  def generate,
    do: @entropy_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)

  def digest(token) when is_binary(token), do: :crypto.hash(:sha256, token)

  @doc "The digest of a token that looks like one of ours."
  def decode(token) when is_binary(token) and byte_size(token) in 32..64 do
    if Regex.match?(~r/^[A-Za-z0-9_-]+$/, token),
      do: {:ok, digest(token)},
      else: {:error, :not_found}
  end

  def decode(_token), do: {:error, :not_found}

  @doc "Where the landing page lives in the web app."
  def path(token), do: "/buddy-invite/" <> token
end
