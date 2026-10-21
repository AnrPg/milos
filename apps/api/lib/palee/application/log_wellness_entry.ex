defmodule Palee.Application.LogWellnessEntry do
  @moduledoc """
  Logs one water, sleep or meal entry for the member (ADR-159 §1): needs the
  health-data consent, validates the kind's value, places it on the member's
  local day, keeps it private, and attaches a meal's photo. An optional
  `organization_slug` records the gym it was logged in.
  """

  alias Palee.Application.{BroadcastUserSync, MealPhotos, WellnessConsent, WellnessInput}
  alias Palee.Wellness

  def call(%{user_id: user_id, account: account} = context, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)
    kind = WellnessInput.param(params, "kind")

    with :ok <- WellnessConsent.require(context),
         {:ok, value} <- Wellness.cast_value(kind, WellnessInput.param(params, "value") || %{}),
         {:ok, photo} <- MealPhotos.prepare(context, Wellness.meal_media_id(value)),
         {:ok, occurrence} <-
           WellnessInput.occurrence(params, now, &Wellness.counts_at(kind, value, &1)),
         {:ok, organization_id} <- WellnessInput.provenance(account, params),
         {:ok, entry} <-
           Wellness.with_context(context, fn ->
             occurrence
             |> Map.merge(%{
               user_id: user_id,
               organization_id: organization_id,
               kind: kind,
               value: value,
               source: "manual",
               journal_visibility: "private"
             })
             |> Wellness.insert_entry()
           end),
         :ok <- attach(context, entry, photo, now) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
        reason: "wellness_logged",
        payload: %{entry_id: entry.id, kind: kind}
      )

      {:ok, entry}
    end
  end

  # The photo could be taken by a parallel request between check and attach;
  # the entry then goes, so nothing half-made stays.
  defp attach(context, entry, photo, now) do
    case MealPhotos.attach(context, entry, photo, now) do
      :ok ->
        :ok

      error ->
        _ = Wellness.with_context(context, fn -> Wellness.delete_entry(entry, now) end)
        error
    end
  end
end
