defmodule MilosTraining.Wellness.Domain.CravingPolicy do
  @moduledoc """
  Λιγούρα (ADR-159 §3, vision §7.7, mockup 22): intensity 1–10, what caused it,
  what happened, and «Χρειάζομαι στήριξη». People log a craving while it is
  happening, so the outcome may come later: a craving saved as still ongoing
  gets one gentle «Πώς πήγε;» after `follow_up_minutes/0`.
  """

  @triggers ~w(stress fatigue boredom social hunger other)
  @outcomes ~w(ongoing resisted ate_off_plan)
  @follow_up_minutes 20
  @note_max 500

  def triggers, do: @triggers
  def outcomes, do: @outcomes
  def follow_up_minutes, do: @follow_up_minutes
  def note_max, do: @note_max
  def intensity_range, do: 1..10

  @doc "When to ask «Πώς πήγε;» for a craving with `outcome`, saved at `now`."
  def follow_up_at(outcome, %DateTime{} = now) when outcome in [nil, "ongoing"],
    do: DateTime.add(now, @follow_up_minutes * 60, :second)

  def follow_up_at(_outcome, _now), do: nil

  @doc "Distinct, known causes in catalogue order."
  def normalize_triggers(triggers) when is_list(triggers) do
    triggers = Enum.map(triggers, &to_string/1)

    if Enum.all?(triggers, &(&1 in @triggers)),
      do: {:ok, Enum.filter(@triggers, &(&1 in triggers))},
      else: {:error, :invalid_craving_trigger}
  end

  def normalize_triggers(nil), do: {:ok, []}
  def normalize_triggers(_triggers), do: {:error, :invalid_craving_trigger}
end
