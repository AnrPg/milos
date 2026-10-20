defmodule MilosTraining.Application.LogCraving do
  @moduledoc """
  Λιγούρα (ADR-159 §3, mockup 22): logs a craving while it happens. The
  outcome may be left for later; a craving saved as still ongoing gets one
  «Πώς πήγε;» follow-up. «Χρειάζομαι στήριξη» is stamped here; who receives
  it is the buddy's business (M12).
  """

  alias MilosTraining.Application.{BroadcastUserSync, WellnessInput}
  alias MilosTraining.Wellness

  def call(%{user_id: user_id, account: account} = context, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    with {:ok, occurrence} <- WellnessInput.occurrence(params, now),
         {:ok, organization_id} <- WellnessInput.provenance(account, params),
         {:ok, fields} <- fields(params, now),
         {:ok, craving} <-
           Wellness.with_context(context, fn ->
             occurrence
             |> Map.merge(fields)
             |> Map.merge(%{
               user_id: user_id,
               organization_id: organization_id,
               journal_visibility: "private",
               follow_up_at: Wellness.craving_follow_up_at(fields[:outcome], now)
             })
             |> Wellness.insert_craving()
           end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
        reason: "craving_logged",
        payload: %{craving_id: craving.id}
      )

      {:ok, craving}
    end
  end

  @doc false
  def fields(params, now, existing \\ nil) do
    with {:ok, triggers} <-
           if(WellnessInput.present?(params, "triggers"),
             do: Wellness.normalize_craving_triggers(WellnessInput.param(params, "triggers")),
             else: {:ok, (existing && existing.triggers) || []}
           ) do
      outcome =
        if WellnessInput.present?(params, "outcome"),
          do: WellnessInput.param(params, "outcome"),
          else: existing && existing.outcome

      fields =
        %{
          intensity: pick(params, "intensity", existing && existing.intensity),
          triggers: triggers,
          note: pick(params, "note", existing && existing.note),
          outcome: outcome,
          outcome_at: outcome_at(outcome, existing, now),
          support_requested_at: support(params, existing, now)
        }

      {:ok, fields}
    end
  end

  defp pick(params, key, current),
    do:
      if(WellnessInput.present?(params, key), do: WellnessInput.param(params, key), else: current)

  defp outcome_at(nil, _existing, _now), do: nil
  defp outcome_at(outcome, %{outcome: outcome, outcome_at: at}, _now) when not is_nil(at), do: at
  defp outcome_at(_outcome, _existing, now), do: now

  # Asking for support is a one-way stamp: once sent, it was sent.
  defp support(params, existing, now) do
    cond do
      existing && existing.support_requested_at -> existing.support_requested_at
      WellnessInput.param(params, "support_requested") == true -> now
      true -> nil
    end
  end
end
