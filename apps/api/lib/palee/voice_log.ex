defmodule Palee.VoiceLog do
  @moduledoc """
  The VoiceLog bounded context (ADR-175, P3-M13): record → transcribe →
  parse → an editable draft training-log entry. Nothing is stored here: the
  audio lives in memory for one request, and the draft is saved only when
  the member confirms it through the normal training-log command.

  Speech to text sits behind the `SpeechTranscriber` port and parsing
  behind the `LogDraftParser` port; the gym's key, the voice switch and the
  usage meter live in AiUsage.
  """

  alias Palee.VoiceLog.{LogDraftParser, SpeechTranscriber}
  alias Palee.VoiceLog.Domain.{Clip, Draft, VoicePolicy}

  defdelegate transcribe(clip, options), to: SpeechTranscriber
  defdelegate parse(input, options), to: LogDraftParser
  defdelegate default_model(), to: LogDraftParser

  defdelegate build_clip(audio_base64, mime_type, duration_ms), to: Clip, as: :build
  defdelegate max_seconds(), to: Clip

  defdelegate normalize_draft(raw), to: Draft, as: :normalize
  defdelegate draft_from_transcript(transcript), to: Draft, as: :from_transcript
  defdelegate clean_transcript(text), to: Draft, as: :transcript

  defdelegate daily_limit(), to: VoicePolicy
  defdelegate remaining(used, limit), to: VoicePolicy
  defdelegate day_start(now), to: VoicePolicy
  defdelegate check(ready?, remaining), to: VoicePolicy
end
