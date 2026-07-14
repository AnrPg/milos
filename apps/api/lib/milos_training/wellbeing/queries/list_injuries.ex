defmodule MilosTraining.Wellbeing.Queries.ListInjuries do
  alias MilosTraining.Wellbeing.WellbeingStore

  def call(filters), do: WellbeingStore.list_injuries(filters)
end
