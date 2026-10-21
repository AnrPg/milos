defmodule Palee.VoiceLog.Domain.VoicePolicy do
  @moduledoc """
  When a member may record (ADR-175), pure.

  Voice logging runs only when the gym switched it on in its AI settings
  with a usable key (`AiUsage.voice_ready?/1`) and the member has drafts
  left today. Each draft is one metered operation (transcription and parse
  share its `operation_id`), so the daily count comes from the meter itself.
  """

  @daily_limit 20

  def daily_limit, do: @daily_limit

  @doc "Drafts left today for `used` operations so far (never negative)."
  def remaining(used, limit \\ @daily_limit) when is_integer(used),
    do: max(limit - used, 0)

  @doc "The start of the UTC day `now` falls in."
  def day_start(%DateTime{} = now),
    do: %{DateTime.truncate(now, :second) | hour: 0, minute: 0, second: 0}

  @doc "`:ok` or the reason recording is refused."
  def check(ready?, remaining)
  def check(false, _remaining), do: {:error, :voice_log_unavailable}
  def check(true, remaining) when remaining <= 0, do: {:error, :voice_log_daily_limit}
  def check(true, _remaining), do: :ok
end
