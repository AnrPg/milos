defmodule Palee.Wellness.Domain.NudgePolicy do
  @moduledoc """
  The two gentle nudges of Ευεξία (ADR-159, board 14 Q2 and Q6). A craving
  left open hears «Πώς πήγε;» once; the afternoon water reminder is the
  member's opt-in and comes at most once a local day, only while the day is
  under half their own goal. Both are re-checked in the member's session, so
  a sweep that raced the member's own update stays silent.
  """

  @doc "Whether a craving still deserves its one follow-up."
  def follow_up_due?(
        %{deleted_at: nil, followed_up_at: nil, follow_up_at: %DateTime{} = at} = c,
        now
      ),
      do: c.outcome in [nil, "ongoing"] and DateTime.compare(at, now) != :gt

  def follow_up_due?(_craving, _now), do: false

  @doc "Whether the water reminder applies to `day` for these preferences and water entries."
  def water_behind?(prefs, day, water_entries) do
    prefs.water_reminder and "water" not in (prefs.hidden_items || []) and
      prefs.water_reminded_on != day and
      water_ml(water_entries, day) * 2 < prefs.water_goal_ml
  end

  defp water_ml(entries, day) do
    entries
    |> Enum.filter(&(&1.kind == "water" and is_nil(&1.deleted_at) and &1.occurred_on == day))
    |> Enum.reduce(0, fn entry, total -> total + (entry.value["ml"] || 0) end)
  end

  def follow_up_dedupe_key(craving_id), do: "craving_follow_up:#{craving_id}"
  def water_dedupe_key(user_id, %Date{} = day), do: "water_reminder:#{user_id}:#{day}"
end
