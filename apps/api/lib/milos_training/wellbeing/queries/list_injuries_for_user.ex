defmodule MilosTraining.Wellbeing.Queries.ListInjuriesForUser do
  alias MilosTraining.Wellbeing.WellbeingStore

  def call(user_id), do: WellbeingStore.list_injuries_for_user(user_id)
end
