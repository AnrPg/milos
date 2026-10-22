defmodule Palee.Notifications.Domain.PayloadTimes do
  @moduledoc """
  ADR-177: the moments a notification mentions, written for its reader.

  Producers put the UTC moment in the payload (`class_starts_at`,
  `event_starts_at`, `starts_at`, `scanned_at`) and, when it differs from
  the gym's, the organiser's zone (`time_zone`). At delivery each moment
  gets its text (`class_when`, `event_when`, `starts_when`, `scanned_when`)
  on the organiser's clock, plus the reader's own time when their zone reads
  it differently («24/10 19:00 Athens · 18:00 your time»). Pure.
  """

  alias Palee.TimeZones.ZonedTime

  @moments [
    {"class_starts_at", "class_when", :date_time},
    {"event_starts_at", "event_when", :date_time},
    {"starts_at", "starts_when", :date_time},
    {"scanned_at", "scanned_when", :time}
  ]

  @doc "The keys of the moments a payload may carry, with their text keys."
  def moments, do: @moments

  @doc "Whether the payload mentions any moment (so the organiser's zone is worth resolving)."
  def mentions_moment?(payload),
    do:
      Enum.any?(@moments, fn {at_key, _when_key, _style} -> ZonedTime.parse(payload[at_key]) end)

  @doc """
  Writes every moment's text for the reader. Without an organiser zone a
  text the producer wrote is kept, and a missing one is written in UTC.
  """
  def localize(payload, organiser_zone, viewer_zone, localize) do
    Enum.reduce(@moments, payload, fn {at_key, when_key, style}, acc ->
      case ZonedTime.parse(acc[at_key]) do
        nil ->
          acc

        at ->
          if ZonedTime.valid?(organiser_zone) or not is_binary(acc[when_key]),
            do:
              Map.put(
                acc,
                when_key,
                ZonedTime.format_for(at, organiser_zone, viewer_zone, localize, style)
              ),
            else: acc
      end
    end)
  end
end
