defmodule MilosTraining.Application.LogWellnessEntry do
  @moduledoc """
  Logs one water, sleep or meal entry for the member (ADR-159 §1): validates
  the kind's value, places it on the member's local day, and keeps it private.
  An optional `organization_slug` records the gym it was logged in.
  """

  alias MilosTraining.Application.{BroadcastUserSync, WellnessInput}
  alias MilosTraining.Wellness

  def call(%{user_id: user_id, account: account} = context, params, now \\ DateTime.utc_now()) do
    now = WellnessInput.usec(now)
    kind = WellnessInput.param(params, "kind")

    with {:ok, value} <- Wellness.cast_value(kind, WellnessInput.param(params, "value") || %{}),
         :ok <- no_media(value),
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
           end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"],
        reason: "wellness_logged",
        payload: %{entry_id: entry.id, kind: kind}
      )

      {:ok, entry}
    end
  end

  # Meal photos arrive with the `meal_photo` media purpose.
  @doc false
  def no_media(value) do
    if Wellness.meal_media_id(value), do: {:error, :invalid_media}, else: :ok
  end
end
