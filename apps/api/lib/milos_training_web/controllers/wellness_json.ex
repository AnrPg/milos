defmodule MilosTrainingWeb.WellnessJSON do
  @moduledoc "Wire shapes of Ημερολόγιο › Ευεξία (ADR-159)."

  alias MilosTraining.Wellness.{Craving, Entry, Preferences}

  def entry(%Entry{} = entry) do
    %{
      id: entry.id,
      kind: entry.kind,
      occurred_at: entry.occurred_at,
      occurred_tz: entry.occurred_tz,
      occurred_on: entry.occurred_on,
      value: entry.value,
      source: entry.source,
      corrected: not is_nil(entry.corrected_at),
      organization_id: entry.organization_id,
      journal_visibility: entry.journal_visibility,
      inserted_at: entry.inserted_at,
      updated_at: entry.updated_at
    }
  end

  def craving(%Craving{} = craving) do
    %{
      id: craving.id,
      occurred_at: craving.occurred_at,
      occurred_tz: craving.occurred_tz,
      occurred_on: craving.occurred_on,
      intensity: craving.intensity,
      triggers: craving.triggers,
      outcome: craving.outcome,
      outcome_at: craving.outcome_at,
      note: craving.note,
      support_requested_at: craving.support_requested_at,
      follow_up_at: craving.follow_up_at,
      organization_id: craving.organization_id,
      journal_visibility: craving.journal_visibility,
      inserted_at: craving.inserted_at,
      updated_at: craving.updated_at
    }
  end

  def preferences(%Preferences{} = prefs) do
    %{
      water_goal_ml: prefs.water_goal_ml,
      glass_ml: prefs.glass_ml,
      sleep_goal_minutes: prefs.sleep_goal_minutes,
      hidden_items: prefs.hidden_items || []
    }
  end

  def overview(payload) do
    %{
      from: payload.from,
      to: payload.to,
      preferences: preferences(payload.preferences),
      days: payload.days,
      week: payload.week,
      entries: Enum.map(payload.entries, &entry/1),
      cravings: Enum.map(payload.cravings, &craving/1)
    }
  end
end
