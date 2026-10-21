defmodule Palee.VoiceLog.Domain.Clip do
  @moduledoc """
  Checks one recorded clip before it is transcribed (ADR-175), pure.

  The clip arrives base64-encoded in the request body and is only ever held
  in memory: it is decoded, checked, handed to the transcriber and dropped.
  The web app records at most `max_seconds/0` and sends 16 kHz mono WAV;
  other common audio types are accepted for other clients.
  """

  @max_seconds 60
  # 60 s of 16 kHz mono 16-bit PCM is 1.92 MB; leave room for headers and
  # slightly higher-rate clients.
  @max_bytes 2_500_000
  @min_bytes 1_000
  @mime_types ~w(audio/wav audio/x-wav audio/mpeg audio/mp4 audio/aac audio/ogg audio/flac audio/webm)

  def max_seconds, do: @max_seconds
  def max_bytes, do: @max_bytes
  def mime_types, do: @mime_types

  @doc """
  `{:ok, %{audio: bytes, mime_type: type}}` for a valid clip, else
  `{:error, :invalid_audio}` or `{:error, :audio_too_long}`.
  """
  def build(audio_base64, mime_type, duration_ms \\ nil)

  def build(audio_base64, mime_type, duration_ms)
      when is_binary(audio_base64) and is_binary(mime_type) do
    type = mime_type |> String.split(";") |> hd() |> String.trim() |> String.downcase()

    cond do
      type not in @mime_types ->
        {:error, :invalid_audio}

      is_integer(duration_ms) and duration_ms > (@max_seconds + 2) * 1_000 ->
        {:error, :audio_too_long}

      # base64 is 4/3 of the bytes; reject before decoding anything huge.
      byte_size(audio_base64) > div(@max_bytes * 4, 3) + 4 ->
        {:error, :audio_too_long}

      true ->
        decode(audio_base64, normalize_type(type))
    end
  end

  def build(_audio, _mime_type, _duration_ms), do: {:error, :invalid_audio}

  defp decode(audio_base64, type) do
    case Base.decode64(audio_base64, ignore: :whitespace) do
      {:ok, bytes} when byte_size(bytes) < @min_bytes -> {:error, :invalid_audio}
      {:ok, bytes} when byte_size(bytes) > @max_bytes -> {:error, :audio_too_long}
      {:ok, bytes} -> {:ok, %{audio: bytes, mime_type: type}}
      :error -> {:error, :invalid_audio}
    end
  end

  defp normalize_type("audio/x-wav"), do: "audio/wav"
  defp normalize_type(type), do: type
end
