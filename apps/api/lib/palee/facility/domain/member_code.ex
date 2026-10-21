defmodule Palee.Facility.Domain.MemberCode do
  @moduledoc """
  The personal QR of Box › Check-in (ADR-155, decision 4): a code the desk
  scans, bound to one member of one box and good for about a minute.

      "M1" ‖ base64url(user_id (16 bytes) ‖ HMAC(key, "member:v1" ‖ user_id ‖ window)[0..11])

  `key` is the box's member-code key (derived from the application secret
  and the organization id by the caller), so a code of one box never opens
  another. The window is #{30} seconds and a code is accepted one window
  either side, like the door code. Pure: callers pass the time.
  """

  alias Palee.Facility.Domain.DoorCode

  @prefix "M1"
  @rotation 30
  @mac_bytes 12

  def rotation, do: @rotation
  def prefix, do: @prefix

  @doc "The code shown now, with when it changes."
  def current(key, user_id, %DateTime{} = now) do
    window = DoorCode.window(now, @rotation)

    %{
      code: sign(key, user_id, window),
      rotation_seconds: @rotation,
      seconds_until_rotation: DoorCode.seconds_until_rotation(now, @rotation),
      expires_at: DoorCode.window_start(window + 1 + DoorCode.grace_windows(), @rotation)
    }
  end

  def sign(key, user_id, window) when is_binary(key) and is_integer(window) do
    uuid = Ecto.UUID.dump!(user_id)
    @prefix <> Base.url_encode64(uuid <> mac(key, uuid, window), padding: false)
  end

  @doc "`{:ok, user_id}` when the code is this box's and current; otherwise an error."
  def verify(key, @prefix <> encoded, %DateTime{} = now) do
    with {:ok, <<uuid::binary-size(16), given::binary-size(@mac_bytes)>>} <-
           Base.url_decode64(encoded, padding: false),
         window = DoorCode.window(now, @rotation),
         true <-
           Enum.any?(
             (window - 1)..(window + 1),
             &Plug.Crypto.secure_compare(mac(key, uuid, &1), given)
           ) do
      Ecto.UUID.load(uuid)
    else
      _invalid -> {:error, :invalid_member_code}
    end
  end

  def verify(_key, _code, _now), do: {:error, :invalid_member_code}

  def member_code?(code) when is_binary(code), do: String.starts_with?(code, @prefix)
  def member_code?(_code), do: false

  defp mac(key, uuid, window),
    do:
      :crypto.mac(:hmac, :sha256, key, "member:v1|" <> uuid <> "|" <> Integer.to_string(window))
      |> binary_part(0, @mac_bytes)
end
