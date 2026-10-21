defmodule Palee.Wellbeing.Queries.InjurySummary do
  alias Palee.Wellbeing.WellbeingStore

  def call(filters), do: WellbeingStore.injury_summary(filters)
end
