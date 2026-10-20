defmodule MilosTraining.Application.SetWellnessPreferences do
  @moduledoc "The member sets their own water goal, glass, sleep goal, hidden items, tile order and the water reminder (ADR-159 §4)."

  alias MilosTraining.Application.{BroadcastUserSync, WellnessInput}
  alias MilosTraining.Wellness

  @fields ~w(water_goal_ml glass_ml sleep_goal_minutes hidden_items item_order water_reminder)

  def call(%{user_id: user_id} = context, params) do
    attrs =
      for key <- @fields,
          WellnessInput.present?(params, key),
          into: %{},
          do: {String.to_existing_atom(key), WellnessInput.param(params, key)}

    with {:ok, prefs} <-
           Wellness.with_context(context, fn -> Wellness.put_preferences(user_id, attrs) end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"], reason: "wellness_preferences")
      {:ok, prefs}
    end
  end
end
