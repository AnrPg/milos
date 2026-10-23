defmodule Palee.Perks.Domain.VerificationToken do
  @moduledoc """
  The partner's verification link of a QR perk (ADR-191 §3), pure.

  A QR claim carries a secret nonce: 32 random bytes, kept in the database
  only as its SHA-256 (`token_hash`). The link the QR opens is a signed
  token (the application signs it with the endpoint secret) whose payload
  names the claim, its organization, the nonce and an expiry:

      %{"v" => 1, "c" => claim_id, "o" => organization_id, "n" => nonce, "x" => unix}

  A link is accepted only when all of these hold: the signature verifies
  (no forging or editing the payload), it is younger than `max_seconds/0`
  and before its own `"x"` (short-lived: a screenshot stops working), the
  nonce matches the stored hash in constant time (a leaked database alone
  can't make links, and the business can revoke a claim), and the claim is
  unused (marking it used is a conditional write, so the link is single-use
  even when two phones scan it at once).

  The short `code` printed under the QR is 8 characters of Crockford
  base32, for the partner to read when the camera won't scan.
  """

  @version 1
  @link_seconds 30 * 60
  @alphabet ~c"0123456789ABCDEFGHJKMNPQRSTVWXYZ"
  @code_length 8

  @doc "How long a verification link lives at most, in seconds."
  def max_seconds, do: @link_seconds

  @doc "A new secret nonce (URL-safe) and the hash stored for it."
  def new_secret do
    nonce = 32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
    {nonce, hash(nonce)}
  end

  @doc "The stored form of a nonce."
  def hash(nonce) when is_binary(nonce),
    do: :sha256 |> :crypto.hash(nonce) |> Base.encode16(case: :lower)

  @doc "Whether a nonce matches a stored hash, in constant time."
  def matches?(stored_hash, nonce) when is_binary(stored_hash) and is_binary(nonce),
    do: Plug.Crypto.secure_compare(stored_hash, hash(nonce))

  def matches?(_stored_hash, _nonce), do: false

  @doc """
  When a link issued at `now` expires: `max_seconds/0` later, never after
  the end (UTC) of the perk's last day. `{:ok, expires_at}` or
  `{:error, :perk_not_available}` when the perk has already ended.
  """
  def expires_at(%DateTime{} = now, valid_until) do
    cap = DateTime.add(now, @link_seconds, :second)

    expires =
      case valid_until do
        %Date{} = until ->
          end_of_day = DateTime.new!(Date.add(until, 1), ~T[00:00:00], "Etc/UTC")
          if DateTime.compare(end_of_day, cap) == :lt, do: end_of_day, else: cap

        nil ->
          cap
      end

    if DateTime.compare(expires, now) == :gt,
      do: {:ok, DateTime.truncate(expires, :second)},
      else: {:error, :perk_not_available}
  end

  @doc "The payload to sign for a claim."
  def payload(claim_id, organization_id, nonce, %DateTime{} = expires_at),
    do: %{
      "v" => @version,
      "c" => claim_id,
      "o" => organization_id,
      "n" => nonce,
      "x" => DateTime.to_unix(expires_at)
    }

  @doc """
  The claim a verified payload names, when it is well formed and not past
  its expiry at `now`: `{:ok, %{claim_id, organization_id, nonce}}`,
  `{:error, :verification_link_expired}` or
  `{:error, :invalid_verification_link}`.
  """
  def parse(
        %{"v" => @version, "c" => claim_id, "o" => organization_id, "n" => nonce, "x" => expires},
        %DateTime{} = now
      )
      when is_binary(claim_id) and is_binary(organization_id) and is_binary(nonce) and
             is_integer(expires) do
    if DateTime.to_unix(now) < expires,
      do: {:ok, %{claim_id: claim_id, organization_id: organization_id, nonce: nonce}},
      else: {:error, :verification_link_expired}
  end

  def parse(_payload, _now), do: {:error, :invalid_verification_link}

  @doc "A fresh short code for under the QR."
  def display_code do
    for <<byte <- :crypto.strong_rand_bytes(@code_length)>>, into: "" do
      <<Enum.at(@alphabet, rem(byte, 32))>>
    end
  end
end
