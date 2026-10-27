defmodule Palee.Infrastructure.Security.DataCipher do
  @moduledoc """
  Encryption at rest for secrets Palee must be able to read back, such as a
  device provider's OAuth tokens (ADR-161): AES-256-GCM with a random 96-bit
  nonce per value, stored as `"v2" <> nonce <> tag <> ciphertext`. (`v1`
  values, under the pre-rename `milos:` context, were never carried over:
  production started from an empty database, TD-109.)

  The key is `config :palee, :data_encryption_key` (32 bytes,
  given as `DATA_ENCRYPTION_KEY` in base64 at runtime). Without one it is
  derived from the endpoint's `secret_key_base` for this one purpose, so a
  deployment works out of the box; setting a dedicated key later needs the
  stored tokens re-issued (people reconnect), which the version prefix
  leaves room for.
  """

  @version "v2"
  @aad "palee:data-at-rest:v2"

  def encrypt(plaintext) when is_binary(plaintext) do
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, plaintext, @aad, 16, true)

    @version <> nonce <> tag <> ciphertext
  end

  def decrypt(<<@version, nonce::binary-12, tag::binary-16, ciphertext::binary>>) do
    case :crypto.crypto_one_time_aead(:aes_256_gcm, key(), nonce, ciphertext, @aad, tag, false) do
      plaintext when is_binary(plaintext) -> {:ok, plaintext}
      :error -> {:error, :undecryptable}
    end
  end

  def decrypt(_value), do: {:error, :undecryptable}

  defp key do
    case Application.get_env(:palee, :data_encryption_key) do
      key when is_binary(key) and byte_size(key) == 32 ->
        key

      _missing ->
        Palee.Infrastructure.Security.PhoenixKeyDerivation.derive("data-at-rest", "v2")
    end
  end
end
