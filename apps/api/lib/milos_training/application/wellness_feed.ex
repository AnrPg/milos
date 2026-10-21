defmodule MilosTraining.Application.WellnessFeed do
  @moduledoc """
  Ευεξία in Ημερολόγιο › Ροή (ADR-159, board 14 Q8): one «Ευεξία» item per
  local day holding that day's water, sleep and meals, so a glass of water
  never floods the feed, and each Λιγούρα as its own item. The member sees
  their own unless they switched the section off (ADR-158 settings); a coach
  sees only entries the member widened to them, while the health-data
  consent stands (row security), and never the member's targets or photos.
  """

  alias MilosTraining.Application.{MealPhotos, WellnessPresenter}
  alias MilosTraining.{Body, Journal, Wellness}

  def day_items(user_id, bound, limit, scope) do
    if section_on?(user_id, scope, "wellness") do
      days = Wellness.list_day_items(user_id, bound, limit, scope)
      extras = owner_extras(user_id, days, scope)
      Enum.map(days, &day(&1, scope, extras))
    else
      []
    end
  end

  def craving_items(user_id, bound, limit, scope) do
    if section_on?(user_id, scope, "cravings") do
      user_id
      |> Wellness.list_craving_items(bound, limit, scope)
      |> Enum.map(&WellnessPresenter.craving/1)
    else
      []
    end
  end

  defp day(%{occurred_on: on, at: at, id: id, entries: entries}, scope, extras) do
    %{
      id: id,
      at: at,
      date: on,
      organization_id: organization_id(scope),
      journal_visibility:
        if(Enum.any?(entries, &shared?/1), do: "coach_can_view", else: "private"),
      summary: extras.summary.(on, entries),
      entries: Enum.map(entries, &WellnessPresenter.entry/1),
      photos: extras.photos
    }
  end

  defp shared?(entry), do: Journal.visibility_reaches_coach?(entry.journal_visibility)

  defp owner_extras(user_id, days, {:owner, _filter}), do: owner_extras(user_id, days, :owner)

  defp owner_extras(user_id, days, :owner) do
    prefs = Wellness.preferences(user_id)

    ids =
      for day <- days,
          entry <- day.entries,
          id = Wellness.meal_media_id(entry.value),
          id != nil,
          do: id

    %{
      summary: fn on, entries ->
        [summary] = Wellness.summarize_days([on], entries, [], %{}, prefs)
        Map.drop(summary, [:cravings, :mood])
      end,
      photos: MealPhotos.present(%{user_id: user_id}, ids)
    }
  end

  defp owner_extras(_user_id, _days, _coach),
    do: %{summary: fn _on, _entries -> nil end, photos: %{}}

  defp organization_id({:coach, organization_id}), do: organization_id
  defp organization_id(_owner), do: nil

  defp section_on?(user_id, {:owner, _filter}, section), do: section_on?(user_id, :owner, section)

  defp section_on?(user_id, :owner, section),
    do: %{user_id: user_id} |> Body.settings(user_id) |> Body.section_on?(section)

  defp section_on?(_user_id, _coach, _section), do: true
end
