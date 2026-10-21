defmodule Palee.Application.SetWellnessPreferences do
  @moduledoc "The member sets their own water goal, glass, sleep goal, hidden items, tile order and the water reminder (ADR-159 §4)."

  alias Palee.Application.{BroadcastUserSync, WellnessInput}
  alias Palee.Wellness

  @fields ~w(water_goal_ml glass_ml sleep_goal_minutes hidden_items item_order water_reminder)a

  def call(%{user_id: user_id} = context, params) do
    attrs =
      for field <- @fields,
          key = Atom.to_string(field),
          WellnessInput.present?(params, key),
          into: %{},
          do: {field, WellnessInput.param(params, key)}

    with {:ok, prefs} <-
           Wellness.with_context(context, fn -> Wellness.put_preferences(user_id, attrs) end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"], reason: "wellness_preferences")
      {:ok, prefs}
    end
  end
end
