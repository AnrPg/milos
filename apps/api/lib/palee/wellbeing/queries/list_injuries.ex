defmodule Palee.Wellbeing.Queries.ListInjuries do
  alias Palee.Wellbeing.WellbeingStore

  def call(filters), do: WellbeingStore.list_injuries(filters)
end
