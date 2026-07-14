defmodule MilosTraining.Wellbeing.Commands.ReportInjury do
  alias MilosTraining.Wellbeing.WellbeingStore

  def call(user_id, actor_id, actor_role, params),
    do: WellbeingStore.report_injury(user_id, actor_id, actor_role, params)
end
