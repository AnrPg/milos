defmodule MilosTrainingWeb.WellnessJSON do
  @moduledoc "Wire shapes of Ημερολόγιο › Ευεξία (ADR-159)."

  alias MilosTraining.Application.WellnessPresenter
  alias MilosTraining.Wellness
  alias MilosTraining.Wellness.Preferences

  defdelegate entry(entry), to: WellnessPresenter
  defdelegate craving(craving), to: WellnessPresenter

  def preferences(%Preferences{} = prefs) do
    %{
      water_goal_ml: prefs.water_goal_ml,
      glass_ml: prefs.glass_ml,
      sleep_goal_minutes: prefs.sleep_goal_minutes,
      hidden_items: prefs.hidden_items || [],
      item_order: Wellness.ordered_items(prefs.item_order || []),
      water_reminder: prefs.water_reminder
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
      cravings: Enum.map(payload.cravings, &craving/1),
      photos: payload.photos,
      photo_capabilities: payload.photo_capabilities,
      consented: payload.consented
    }
  end
end
