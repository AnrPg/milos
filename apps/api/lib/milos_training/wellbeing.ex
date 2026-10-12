defmodule MilosTraining.Wellbeing do
  alias MilosTraining.Wellbeing.Commands.{MarkHealed, ReportInjury}
  alias MilosTraining.Wellbeing.Domain.InjuryRiskPolicy

  alias MilosTraining.Wellbeing.Queries.{
    GetInjuryForUser,
    InjurySummary,
    ListActiveInjuriesForUsers,
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

  # ADR-114 injury-aware workout safety warnings.
  defdelegate list_active_injuries_for_users(user_ids),
    to: ListActiveInjuriesForUsers,
    as: :call

  @doc "Own active injuries the user may see (incl. personal self-reports)."
  def list_active_injuries_for_user(user_id),
    do: user_id |> list_injuries_for_user() |> Enum.filter(&(&1.status == "active"))

  defdelegate evaluate_injury_risk(injuries, exercises), to: InjuryRiskPolicy, as: :evaluate
  defdelegate injury_risk_analytics_facts(evaluation), to: InjuryRiskPolicy, as: :analytics_facts
  defdelegate max_injury_warning_level(levels), to: InjuryRiskPolicy, as: :max_level

  # ADR-107 reviewed tenant export/purge. This context owns its table list and
  # retention policy; the shared executor only runs what this policy declares,
  # always inside a RepoContext session for the purge's tenant.
  def tenant_data_policy, do: MilosTraining.Wellbeing.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
