defmodule Palee.Application.VoiceLogDrafts do
  @moduledoc """
  Voice logging (ADR-175): a member records what they did, the clip is
  transcribed and parsed into a draft training-log entry, and the draft goes
  back to the member's log form. Nothing is saved here — the entry is
  created only when the member confirms the form (the normal
  `training_log.create` command) — and the audio is dropped as soon as the
  transcriber answered.

  Runs only when the gym switched voice logging on with a usable key, and
  at most `VoiceLog.daily_limit/0` recordings per member per UTC day
  (counted from the meter, so a failed transcription the provider did not
  bill does not count). The
  transcription and the parse of one recording share an `operation_id` and
  are metered for the gym under the feature `voice_log` (ADR-152).

  If parsing fails after a good transcription, the member still gets the
  transcript as the entry's note (`parsed: false`), never an error.
  """

  alias Palee.{AiUsage, VoiceLog}

  @feature "voice_log"

  def feature, do: @feature

  @doc "Whether the member may record now, and how many drafts are left today."
  def availability(context, now \\ DateTime.utc_now()) do
    ready? = AiUsage.voice_ready?(AiUsage.get_settings(context))
    remaining = if ready?, do: remaining(context, now), else: 0

    %{
      available: ready? and remaining > 0,
      enabled: ready?,
      max_seconds: VoiceLog.max_seconds(),
      daily_limit: VoiceLog.daily_limit(),
      remaining_today: remaining
    }
  end

  @doc """
  `{:ok, %{transcript, draft, parsed}}` for one recording. `params`:
  `audio_base64`, `mime_type`, optional `duration_ms` and `locale`.
  """
  def draft(context, params, now \\ DateTime.utc_now()) do
    settings = AiUsage.get_settings(context)
    ready? = AiUsage.voice_ready?(settings)
    remaining = if ready?, do: remaining(context, now), else: 0

    with :ok <- VoiceLog.check(ready?, remaining),
         {:ok, clip} <-
           VoiceLog.build_clip(
             Map.get(params, :audio_base64),
             Map.get(params, :mime_type),
             Map.get(params, :duration_ms)
           ) do
      locale = locale(Map.get(params, :locale))
      metering = metering(context)

      with {:ok, transcript} <- transcribe(Map.put(clip, :locale, locale), metering) do
        {:ok, parse(context, settings, transcript, locale, metering)}
      end
    end
  end

  defp transcribe(clip, metering) do
    case VoiceLog.transcribe(clip, %{metering: metering}) do
      {:ok, text} ->
        case VoiceLog.clean_transcript(text) do
          nil -> {:error, :no_speech}
          transcript -> {:ok, transcript}
        end

      {:error, _reason} ->
        {:error, :transcription_unavailable}
    end
  end

  defp parse(context, settings, transcript, locale, metering) do
    options = %{
      api_key: settings.api_key,
      model: AiUsage.settings_model(settings, VoiceLog.default_model()),
      metering: metering
    }

    with {:ok, raw} <- ask(context, %{transcript: transcript, locale: locale}, options),
         {:ok, draft} <- VoiceLog.normalize_draft(raw) do
      %{transcript: transcript, draft: draft, parsed: true}
    else
      {:error, _reason} ->
        %{
          transcript: transcript,
          draft: VoiceLog.draft_from_transcript(transcript),
          parsed: false
        }
    end
  end

  defp ask(context, input, options) do
    case VoiceLog.parse(input, options) do
      {:error, :parser_key_rejected} = error ->
        _ = AiUsage.put_settings(context, %{key_status: "rejected", key_checked_at: now()})
        error

      {:ok, raw} ->
        mark_key_valid(context)
        {:ok, raw}

      error ->
        error
    end
  end

  defp mark_key_valid(context) do
    case AiUsage.get_settings(context) do
      %{key_status: "valid"} -> :ok
      _other -> AiUsage.put_settings(context, %{key_status: "valid", key_checked_at: now()})
    end
  end

  defp remaining(context, now) do
    summary =
      AiUsage.usage_summary(context, %{
        from: VoiceLog.day_start(now),
        feature: @feature,
        # Every recording is transcribed once, so its calls count drafts.
        agent: "voice_transcribe",
        user_id: context.user_id
      })

    used = summary.rows |> Enum.map(& &1.operations) |> Enum.sum()
    VoiceLog.remaining(used, VoiceLog.daily_limit())
  end

  defp metering(context),
    do: %{
      operation_id: Ecto.UUID.generate(),
      feature: @feature,
      organization_id: context.organization_id,
      user_id: context.user_id
    }

  defp locale(locale) when is_binary(locale) do
    if Regex.match?(~r/^[a-z]{2}(-[A-Z]{2})?$/, locale), do: locale, else: "el"
  end

  defp locale(_locale), do: "el"

  defp now, do: DateTime.utc_now()
end
