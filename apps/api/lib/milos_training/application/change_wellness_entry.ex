defmodule MilosTraining.Application.ChangeWellnessEntry do
  @moduledoc """
  The member corrects or removes one of their wellness entries (ADR-159 §1).
  A correction of a device reading keeps the member's version from then on.
  """

  alias MilosTraining.Application.{BroadcastUserSync, LogWellnessEntry, WellnessInput}
  alias MilosTraining.Wellness

  def update(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    Wellness.with_context(context, fn ->
      with %{} = entry <- Wellness.get_entry(id, user_id) || {:error, :not_found},
           {:ok, attrs} <- attrs(entry, params, now),
           {:ok, entry} <- Wellness.change_entry(entry, attrs, now) do
        {:ok, entry}
      end
    end)
    |> broadcast(user_id, "wellness_changed")
  end

  def delete(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    Wellness.with_context(context, fn ->
      case Wellness.get_entry(id, user_id) do
        nil -> {:error, :not_found}
        entry -> Wellness.delete_entry(entry, now)
      end
    end)
    |> broadcast(user_id, "wellness_deleted")
  end

  # A new value replaces the old one whole; a new time moves the entry,
  # keeping its zone unless another is given.
  defp attrs(entry, params, now) do
    with {:ok, value} <- value(entry, params),
         :ok <- LogWellnessEntry.no_media(value),
         {:ok, occurrence} <-
           WellnessInput.occurrence(
             %{
               "occurred_at" => WellnessInput.param(params, "occurred_at") || entry.occurred_at,
               "occurred_tz" => WellnessInput.param(params, "occurred_tz") || entry.occurred_tz
             },
             now,
             &Wellness.counts_at(entry.kind, value, &1)
           ) do
      {:ok, Map.put(occurrence, :value, value)}
    end
  end

  defp value(entry, params) do
    if WellnessInput.present?(params, "value"),
      do: Wellness.cast_value(entry.kind, WellnessInput.param(params, "value") || %{}),
      else: {:ok, entry.value}
  end

  defp broadcast({:ok, entry} = result, user_id, reason) do
    BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
      reason: reason,
      payload: %{entry_id: entry.id, kind: entry.kind}
    )

    result
  end

  defp broadcast(error, _user_id, _reason), do: error
end
