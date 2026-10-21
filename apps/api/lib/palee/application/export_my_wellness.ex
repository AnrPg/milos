defmodule Palee.Application.ExportMyWellness do
  @moduledoc """
  Export per section (ADR-159, board 14 Q9): the member's wellness entries
  with their targets, and/or their cravings, as JSON; meal photos come as
  short-lived signed links to the full rendition, so the file is the
  member's to keep without opening the private bucket.
  """

  alias Palee.Application.{MealPhotos, WellnessInput, WellnessPresenter}
  alias Palee.Wellness

  def call(%{user_id: user_id} = context, params, now \\ DateTime.utc_now()) do
    with {:ok, sections} <- WellnessInput.sections(params) do
      rows = Wellness.with_context(context, fn -> Wellness.export(user_id, sections) end)
      entries = Map.get(rows, "wellness", [])

      exported =
        Map.new(rows, fn
          {"wellness", entries} ->
            {"wellness",
             %{
               preferences: wellness_preferences(context, user_id),
               entries: Enum.map(entries, &WellnessPresenter.entry/1)
             }}

          {"cravings", cravings} ->
            {"cravings", %{cravings: Enum.map(cravings, &WellnessPresenter.craving/1)}}
        end)

      photo_ids = entries |> Enum.map(&Wellness.meal_media_id(&1.value)) |> Enum.reject(&is_nil/1)

      {:ok,
       %{
         exported_at: now,
         sections: exported,
         photos: if(photo_ids == [], do: %{}, else: MealPhotos.present(context, photo_ids))
       }}
    end
  end

  defp wellness_preferences(context, user_id) do
    prefs = Wellness.with_context(context, fn -> Wellness.preferences(user_id) end)

    Map.take(prefs, [
      :water_goal_ml,
      :glass_ml,
      :sleep_goal_minutes,
      :hidden_items,
      :item_order,
      :water_reminder
    ])
  end
end
