defmodule MilosTraining.Analytics.Commands.UpsertExerciseCatalogEntry do
  alias MilosTraining.Analytics.AnalyticsStore

  def call(params), do: AnalyticsStore.upsert_exercise_catalog_entry(params)
end
