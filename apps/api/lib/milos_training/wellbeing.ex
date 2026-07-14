defmodule MilosTraining.Wellbeing do
  alias MilosTraining.Wellbeing.Commands.{MarkHealed, ReportInjury}

  alias MilosTraining.Wellbeing.Queries.{
    GetInjuryForUser,
    InjurySummary,
    ListInjuries,
    ListInjuriesForUser
  }

  defdelegate report_injury(user_id, actor_id, actor_role, params), to: ReportInjury, as: :call
  defdelegate mark_healed(injury_report_id, actor_id, healed_on \\ nil), to: MarkHealed, as: :call
  defdelegate get_injury_for_user(user_id, injury_report_id), to: GetInjuryForUser, as: :call
  defdelegate list_injuries_for_user(user_id), to: ListInjuriesForUser, as: :call
  defdelegate list_injuries(filters \\ %{}), to: ListInjuries, as: :call
  defdelegate injury_summary(filters \\ %{}), to: InjurySummary, as: :call
end
