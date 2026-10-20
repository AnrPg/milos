defmodule MilosTraining.Wallet.Domain.PassToken do
  @moduledoc """
  The barcode on a Wallet card (ADR-155, decision 5): a long-lived member
  token the desk scans with the same scanner as the personal QR.

      "W1" ‖ base64url(serial (16 bytes) ‖ HMAC(key, "wallet:v1" ‖ serial)[0..15])

  It names the pass by its serial and is signed with the Wallet key (derived
  from the application secret by the caller), so it cannot be made up. It
  does not expire by itself: the pass row is the source of truth, and a
  revoked pass stops scanning the moment it is revoked. Pure.
  """

  @prefix "W1"
  @mac_bytes 16

  def prefix, do: @prefix

  def sign(key, serial) when is_binary(key) and is_binary(serial) do
    uuid = Ecto.UUID.dump!(serial)
    @prefix <> Base.url_encode64(uuid <> mac(key, uuid), padding: false)
  end

  @doc "`{:ok, serial}` for a genuine token; it says nothing about revocation."
  def verify(key, @prefix <> encoded) when is_binary(key) do
    with {:ok, <<uuid::binary-size(16), given::binary-size(@mac_bytes)>>} <-
           Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(mac(key, uuid), given) do
      Ecto.UUID.load(uuid)
    else
      _invalid -> {:error, :invalid_pass}
    end
  end

  def verify(_key, _token), do: {:error, :invalid_pass}

  def pass_token?(token) when is_binary(token), do: String.starts_with?(token, @prefix)
  def pass_token?(_token), do: false

  defp mac(key, uuid),
    do: :crypto.mac(:hmac, :sha256, key, "wallet:v1|" <> uuid) |> binary_part(0, @mac_bytes)
end
