defmodule Palee.Application.EraseMyWellness do
  @moduledoc """
  «Διαγραφή όλων» per section (ADR-147 D11, ADR-159 §4): `wellness` removes
  every water, sleep and meal entry, the meal photos and the targets; `cravings` removes every
  craving. Irreversible; the web asks for confirmation first.
  """

  alias Palee.Application.{BroadcastUserSync, MealPhotos, WellnessInput}
  alias Palee.{Insights, Wellness}

  def call(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, sections} <- WellnessInput.sections(params),
         {:ok, counts} <-
           Wellness.with_context(context, fn ->
             Wellness.transaction(fn -> Wellness.erase(user_id, sections, now) end)
           end),
         :ok <- if("wellness" in sections, do: MealPhotos.release_all(context), else: :ok),
         # ADR-166: insights drawn from the erased data go with it.
         :ok <- Insights.with_context(context, fn -> Insights.delete_all(user_id) end) do
      BroadcastUserSync.for_user(user_id, ["my_wellbeing"], reason: "wellness_erased")
      {:ok, counts}
    end
  end
end
