defmodule MilosTraining.Wellbeing.Queries.InjurySummary do
  alias MilosTraining.Wellbeing.WellbeingStore

  def call(filters), do: WellbeingStore.injury_summary(filters)
end
