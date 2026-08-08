defmodule MilosTraining.Wellbeing do
  alias MilosTraining.Wellbeing.Commands.{MarkHealed, ReportInjury}

  alias MilosTraining.Wellbeing.Queries.{
    GetInjuryForUser,
    InjurySummary,
    ListInjuries,
    ListInjuriesForUser
  }

  alias MilosTraining.Wellbeing.WellbeingStore

  def with_tenant_context(context, fun) when is_function(fun, 0),
    do: WellbeingStore.with_context(context, fun)

  defdelegate report_injury(user_id, actor_id, actor_role, params), to: ReportInjury, as: :call
  defdelegate mark_healed(injury_report_id, actor_id, healed_on \\ nil), to: MarkHealed, as: :call
  defdelegate get_injury_for_user(user_id, injury_report_id), to: GetInjuryForUser, as: :call
  defdelegate list_injuries_for_user(user_id), to: ListInjuriesForUser, as: :call

  def list_injuries_for_user(context, user_id),
    do: with_tenant_context(context, fn -> list_injuries_for_user(user_id) end)

  defdelegate list_injuries(filters \\ %{}), to: ListInjuries, as: :call
  defdelegate injury_summary(filters \\ %{}), to: InjurySummary, as: :call
end
