defmodule MilosTraining.Wellbeing.WellbeingStore do
  @behaviour MilosTraining.Wellbeing.Ports.WellbeingStore

  def report_injury(user_id, actor_id, actor_role, params),
    do: adapter().report_injury(user_id, actor_id, actor_role, params)

  def mark_healed(injury_report_id, actor_id, healed_on),
    do: adapter().mark_healed(injury_report_id, actor_id, healed_on)

  def get_injury_for_user(user_id, injury_report_id),
    do: adapter().get_injury_for_user(user_id, injury_report_id)

  def list_injuries_for_user(user_id), do: adapter().list_injuries_for_user(user_id)
  def list_injuries(filters), do: adapter().list_injuries(filters)
  def injury_summary(filters), do: adapter().injury_summary(filters)

  defp adapter, do: Application.fetch_env!(:milos_training, :wellbeing_store)
end
