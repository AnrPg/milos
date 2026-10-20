defmodule MilosTraining.Facility.Domain.DoorCode do
  @moduledoc """
  The rotating door QR (ADR-155, decision 1): no table, a code is

      HMAC-SHA256(key, "door:v1" ‖ location_id ‖ rotation ‖ window)

  truncated to 96 bits, where `window` is the number of `rotation`-second
  periods since the epoch and `key` is the location's door key (derived from
  its seed and the application secret by the caller). A code is accepted in
  its own window and one window either side, so a scan at the turn of a
  window still works while a screenshot dies within about a minute.

  `batch/5` signs the next few windows so the door display keeps rotating
  through a short network drop. A batch never reaches further than
  `#{120}` seconds ahead, so a leaked batch is useless about two minutes
  later. Pure: callers pass the time.
  """

  @mac_bytes 12
  @grace_windows 1
  @offline_horizon_seconds 120

  @type key :: binary()

  @doc "The window an instant falls in."
  def window(%DateTime{} = now, rotation) when is_integer(rotation) and rotation > 0,
    do: div(DateTime.to_unix(now), rotation)

  @doc "When a window starts."
  def window_start(window, rotation), do: DateTime.from_unix!(window * rotation)

  @doc "Seconds until the code on the display changes."
  def seconds_until_rotation(%DateTime{} = now, rotation),
    do: rotation - rem(DateTime.to_unix(now), rotation)

  @doc "The code of one window."
  def sign(key, location_id, window, rotation)
      when is_binary(key) and is_binary(location_id) and is_integer(window) do
    :crypto.mac(:hmac, :sha256, key, message(location_id, window, rotation))
    |> binary_part(0, @mac_bytes)
    |> Base.url_encode64(padding: false)
  end

  @doc "The code shown now."
  def current(key, location_id, %DateTime{} = now, rotation),
    do: sign(key, location_id, window(now, rotation), rotation)

  @doc """
  Whether `code` is this location's code now, within one window of grace.
  Comparison is constant-time.
  """
  def verify(key, location_id, code, %DateTime{} = now, rotation) when is_binary(code) do
    current = window(now, rotation)

    if Enum.any?(
         (current - @grace_windows)..(current + @grace_windows),
         &Plug.Crypto.secure_compare(sign(key, location_id, &1, rotation), code)
       ),
       do: :ok,
       else: {:error, :invalid_door_code}
  end

  def verify(_key, _location_id, _code, _now, _rotation), do: {:error, :invalid_door_code}

  @doc "How many windows an offline batch holds for a rotation."
  def batch_size(rotation), do: max(div(@offline_horizon_seconds, rotation), 2)

  @doc """
  The codes of the current window and the next ones, each with the moment
  the display shows it (`shows_from`) and the last moment a scan of it is
  accepted (`valid_until`, one window of grace after its own).
  """
  def batch(key, location_id, %DateTime{} = now, rotation, count \\ nil) do
    first = window(now, rotation)
    count = min(count || batch_size(rotation), batch_size(rotation))

    Enum.map(first..(first + count - 1), fn window ->
      %{
        code: sign(key, location_id, window, rotation),
        shows_from: window_start(window, rotation),
        valid_until: window_start(window + 1 + @grace_windows, rotation)
      }
    end)
  end

  def offline_horizon_seconds, do: @offline_horizon_seconds
  def grace_windows, do: @grace_windows

  defp message(location_id, window, rotation),
    do: "door:v1|#{String.downcase(location_id)}|#{rotation}|#{window}"
end
