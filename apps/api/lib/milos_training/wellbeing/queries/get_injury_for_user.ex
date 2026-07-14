defmodule MilosTraining.Wellbeing.Queries.GetInjuryForUser do
  alias MilosTraining.Wellbeing.WellbeingStore

  def call(user_id, injury_report_id),
    do: WellbeingStore.get_injury_for_user(user_id, injury_report_id)
end
