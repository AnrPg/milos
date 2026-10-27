defmodule Palee.Email.Domain.UnsubscribeToken do
  @moduledoc """
  The signed one-click unsubscribe token of a transactional email
  (ADR-212, RFC 8058). It names the address only by its suppression
  digest, so the link carries no readable address:

      digest (32 bytes) | kind length (1) | kind | locale | HMAC-SHA256 (first 16 bytes)

  url-safe base64 without padding. The key is derived from the endpoint
  secret for this one purpose; the token does not expire, because a reader
  may unsubscribe from an old email.
  """

  @mac_bytes 16
  @digest_bytes 32
  @max_kind 64
  @locale ~r/\A[a-z]{2}(_[A-Z]{2})?\z/

  @type claims :: %{digest: binary(), kind: String.t(), locale: String.t()}

  @doc "The token for `claims`, signed with `key`."
  @spec sign(binary(), claims()) :: String.t()
  def sign(key, %{digest: digest, kind: kind, locale: locale})
      when byte_size(digest) == @digest_bytes and byte_size(kind) in 1..@max_kind do
    payload = digest <> <<byte_size(kind)>> <> kind <> locale
    Base.url_encode64(payload <> mac(key, payload), padding: false)
  end

  @doc "`{:ok, claims}` for a token `key` signed, else `:error`."
  @spec verify(binary(), String.t()) :: {:ok, claims()} | :error
  def verify(key, token) when is_binary(token) and byte_size(token) < 400 do
    with {:ok, raw} <- Base.url_decode64(token, padding: false),
         true <- byte_size(raw) > @digest_bytes + 1 + @mac_bytes,
         payload_size = byte_size(raw) - @mac_bytes,
         <<payload::binary-size(payload_size), given::binary>> = raw,
         true <- Plug.Crypto.secure_compare(mac(key, payload), given),
         <<digest::binary-size(@digest_bytes), kind_size, rest::binary>> <- payload,
         <<kind::binary-size(kind_size), locale::binary>> <- rest,
         true <- Regex.match?(@locale, locale) do
      {:ok, %{digest: digest, kind: kind, locale: locale}}
    else
      _invalid -> :error
    end
  end

  def verify(_key, _token), do: :error

  defp mac(key, payload),
    do: :crypto.mac(:hmac, :sha256, key, payload) |> binary_part(0, @mac_bytes)
end
