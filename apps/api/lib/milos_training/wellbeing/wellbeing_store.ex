defmodule MilosTraining.Wellbeing.WellbeingStore do
  @behaviour MilosTraining.Wellbeing.Ports.WellbeingStore

  @adapter Application.compile_env(
             :milos_training,
             :wellbeing_store,
             MilosTraining.Infrastructure.Wellbeing.EctoWellbeingStore
           )

  defdelegate report_injury(user_id, actor_id, actor_role, params), to: @adapter
  defdelegate mark_healed(injury_report_id, actor_id, healed_on), to: @adapter
  defdelegate get_injury_for_user(user_id, injury_report_id), to: @adapter
  defdelegate list_injuries_for_user(user_id), to: @adapter
  defdelegate list_injuries(filters), to: @adapter
  defdelegate injury_summary(filters), to: @adapter
end
