defmodule Palee.Application.ChangeCraving do
  @moduledoc """
  The member updates a craving (most often its outcome, after «Πώς πήγε;») or
  removes it (ADR-159 §3). Settling the outcome cancels a pending follow-up.
  """

  alias Palee.Application.{BroadcastUserSync, LogCraving, WellnessConsent, WellnessInput}
  alias Palee.Wellness

  def update(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    with :ok <- WellnessConsent.require(context),
         {:ok, changed, previous} <-
           Wellness.with_context(context, fn -> change(id, user_id, params, now) end),
         :ok <- LogCraving.request_support(context, changed, previous) do
      broadcast({:ok, changed}, user_id, "craving_changed")
    end
  end

  defp change(id, user_id, params, now) do
    with %{} = craving <- Wellness.get_craving(id, user_id) || {:error, :not_found},
         {:ok, fields} <- LogCraving.fields(params, now, craving),
         {:ok, occurrence} <- occurrence(craving, params, now),
         attrs =
           fields
           |> Map.merge(occurrence)
           |> Map.put(:follow_up_at, follow_up(craving, fields.outcome, now)),
         {:ok, changed} <- Wellness.change_craving(craving, attrs) do
      {:ok, changed, craving.support_requested_at}
    end
  end

  def delete(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    Wellness.with_context(context, fn ->
      case Wellness.get_craving(id, user_id) do
        nil -> {:error, :not_found}
        craving -> Wellness.delete_craving(craving, now)
      end
    end)
    |> broadcast(user_id, "craving_deleted")
  end

  defp occurrence(craving, params, now) do
    WellnessInput.occurrence(
      %{
        "occurred_at" => WellnessInput.param(params, "occurred_at") || craving.occurred_at,
        "occurred_tz" => WellnessInput.param(params, "occurred_tz") || craving.occurred_tz
      },
      now
    )
  end

  # The follow-up stays as first planned while the craving is ongoing, and
  # is dropped once the member says how it went.
  defp follow_up(craving, outcome, now) when outcome in [nil, "ongoing"],
    do: craving.follow_up_at || Wellness.craving_follow_up_at(outcome, now)

  defp follow_up(_craving, _outcome, _now), do: nil

  defp broadcast({:ok, craving} = result, user_id, reason) do
    BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
      reason: reason,
      payload: %{craving_id: craving.id}
    )

    result
  end

  defp broadcast(error, _user_id, _reason), do: error
end
