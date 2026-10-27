defmodule Palee.Infrastructure.Security.DataCipherTest do
  use ExUnit.Case, async: true

  alias Palee.Infrastructure.Security.{DataCipher, PhoenixKeyDerivation}

  test "values round-trip under the v2 format" do
    ciphertext = DataCipher.encrypt("garmin-token")

    assert "v2" <> _rest = ciphertext
    assert DataCipher.decrypt(ciphertext) == {:ok, "garmin-token"}
  end

  test "a value sealed under the pre-rename milos context does not decrypt" do
    base = PaleeWeb.Endpoint.config(:secret_key_base)
    purpose_key = Plug.Crypto.KeyGenerator.generate(base, "milos:data-at-rest", length: 32)
    key = :crypto.mac(:hmac, :sha256, purpose_key, "v1")
    nonce = :crypto.strong_rand_bytes(12)

    {ciphertext, tag} =
      :crypto.crypto_one_time_aead(
        :aes_256_gcm,
        key,
        nonce,
        "x",
        "milos:data-at-rest:v1",
        16,
        true
      )

    assert DataCipher.decrypt("v1" <> nonce <> tag <> ciphertext) == {:error, :undecryptable}
  end

  test "derived keys are bound to the palee context" do
    base = PaleeWeb.Endpoint.config(:secret_key_base)
    purpose_key = Plug.Crypto.KeyGenerator.generate(base, "palee:door-code", length: 32)

    assert PhoenixKeyDerivation.derive("door-code", "loc|seed") ==
             :crypto.mac(:hmac, :sha256, purpose_key, "loc|seed")
  end
end
