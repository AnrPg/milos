defmodule Palee.Analytics.Commands.UpsertExerciseCatalogEntry do
  alias Palee.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.upsert_exercise_catalog_entry(params)
end
