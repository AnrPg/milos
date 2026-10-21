defmodule Palee.Facility.Domain.StaticMemberCode do
  @moduledoc """
  The persistent personal code of a box that keeps static member codes
  (board 10, Q5; ADR-155). One code per member and box, named by the serial
  of its `facility_member_codes` row, signed with the box's member key:

      prefix ‖ base64url(serial (16 bytes) ‖ HMAC(key, "member-static:v1" ‖ channel ‖ serial)[0..15])

  The same code reaches the desk two ways, told apart only to record the
  check-in method: `"S1"` in the app's QR (`:app`, method `member_qr`) and
  `"W1"` on the Wallet card (`:wallet`, method `wallet`). Both name the same
  row, so revoking the code stops both at once. It never expires by itself.
  Pure.
  """

  @prefixes %{app: "S1", wallet: "W1"}
  @mac_bytes 16

  def prefixes, do: @prefixes

  def sign(key, serial, channel) when is_binary(key) and channel in [:app, :wallet] do
    uuid = Ecto.UUID.dump!(serial)
    @prefixes[channel] <> Base.url_encode64(uuid <> mac(key, uuid, channel), padding: false)
  end

  @doc "`{:ok, serial, channel}` for a genuine code; it says nothing about revocation."
  def verify(key, code) when is_binary(key) and is_binary(code) do
    with {:ok, channel, encoded} <- split(code),
         {:ok, <<uuid::binary-size(16), given::binary-size(@mac_bytes)>>} <-
           Base.url_decode64(encoded, padding: false),
         true <- Plug.Crypto.secure_compare(mac(key, uuid, channel), given),
         {:ok, serial} <- Ecto.UUID.load(uuid) do
      {:ok, serial, channel}
    else
      _invalid -> {:error, :invalid_member_code}
    end
  end

  def verify(_key, _code), do: {:error, :invalid_member_code}

  @doc "The channel a code's prefix claims, or nil."
  def channel("S1" <> _rest), do: :app
  def channel("W1" <> _rest), do: :wallet
  def channel(_code), do: nil

  defp split("S1" <> encoded), do: {:ok, :app, encoded}
  defp split("W1" <> encoded), do: {:ok, :wallet, encoded}
  defp split(_code), do: :error

  defp mac(key, uuid, channel),
    do:
      :crypto.mac(:hmac, :sha256, key, "member-static:v1|#{channel}|" <> uuid)
      |> binary_part(0, @mac_bytes)
end
