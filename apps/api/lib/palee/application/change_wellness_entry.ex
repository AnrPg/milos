defmodule Palee.Application.ChangeWellnessEntry do
  @moduledoc """
  The member corrects or removes one of their wellness entries (ADR-159 §1).
  A correction of a device reading keeps the member's version from then on.
  A meal's photo follows its entry: a new one is attached, a replaced or
  removed one is deleted, and deleting the entry deletes its photo.
  """

  alias Palee.Application.{BroadcastUserSync, MealPhotos, WellnessConsent, WellnessInput}
  alias Palee.Wellness

  def update(%{user_id: user_id} = context, id, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    with :ok <- WellnessConsent.require(context),
         %{} = entry <- owned(context, id, user_id),
         {:ok, attrs} <- attrs(entry, params, now),
         {:ok, photo} <- new_photo(context, entry, attrs.value),
         {:ok, changed} <-
           Wellness.with_context(context, fn -> Wellness.change_entry(entry, attrs, now) end),
         :ok <- MealPhotos.attach(context, changed, photo, now),
         :ok <- release_replaced(context, entry, changed) do
      broadcast({:ok, changed}, user_id, "wellness_changed")
    end
  end

  def delete(%{user_id: user_id} = context, id, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)

    with %{} = entry <- owned(context, id, user_id),
         {:ok, deleted} <-
           Wellness.with_context(context, fn -> Wellness.delete_entry(entry, now) end),
         :ok <- MealPhotos.release(context, Wellness.meal_media_id(entry.value)) do
      broadcast({:ok, deleted}, user_id, "wellness_deleted")
    end
  end

  defp owned(context, id, user_id) do
    Wellness.with_context(context, fn -> Wellness.get_entry(id, user_id) end) ||
      {:error, :not_found}
  end

  # A new value replaces the old one whole; a new time moves the entry,
  # keeping its zone unless another is given.
  defp attrs(entry, params, now) do
    with {:ok, value} <- value(entry, params),
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

  defp new_photo(context, entry, value) do
    id = Wellness.meal_media_id(value)

    if is_nil(id) or id == Wellness.meal_media_id(entry.value),
      do: {:ok, nil},
      else: MealPhotos.prepare(context, id)
  end

  defp release_replaced(context, before, changed) do
    old = Wellness.meal_media_id(before.value)

    if old && old != Wellness.meal_media_id(changed.value),
      do: MealPhotos.release(context, old),
      else: :ok
  end

  defp broadcast({:ok, entry} = result, user_id, reason) do
    BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
      reason: reason,
      payload: %{entry_id: entry.id, kind: entry.kind}
    )

    result
  end
end
