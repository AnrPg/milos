defmodule Palee.Wellbeing.WellbeingStore do
  @behaviour Palee.Wellbeing.Ports.WellbeingStore

  alias Palee.Infrastructure.Tenancy.RepoContext

  def with_context(context, fun) when is_function(fun, 0),
    do: RepoContext.run(context, fun)

  def report_injury(user_id, actor_id, actor_role, params),
    do: adapter().report_injury(user_id, actor_id, actor_role, params)

  def mark_healed(injury_report_id, actor_id, healed_on),
    do: adapter().mark_healed(injury_report_id, actor_id, healed_on)

  def update_injury(injury_report_id, actor_id, build),
    do: adapter().update_injury(injury_report_id, actor_id, build)

  def reopen_injury(injury_report_id, actor_id),
    do: adapter().reopen_injury(injury_report_id, actor_id)

  def get_injury_for_user(user_id, injury_report_id),
    do: adapter().get_injury_for_user(user_id, injury_report_id)

  def list_injuries_for_user(user_id), do: adapter().list_injuries_for_user(user_id)

  def list_active_tenant_injuries_for_users(user_ids),
    do: adapter().list_active_tenant_injuries_for_users(user_ids)

  def list_injuries(filters), do: adapter().list_injuries(filters)
  def injury_summary(filters), do: adapter().injury_summary(filters)

  def create_check_in(attrs), do: adapter().create_check_in(attrs)
  def delete_check_in(id, user_id, now), do: adapter().delete_check_in(id, user_id, now)
  def get_check_in_for_user(id, user_id), do: adapter().get_check_in_for_user(id, user_id)

  def set_check_in_visibility(id, user_id, rung),
    do: adapter().set_check_in_visibility(id, user_id, rung)

  def move_check_ins(user_id, from, to), do: adapter().move_check_ins(user_id, from, to)

  def list_check_in_items(user_id, bound, limit, scope),
    do: adapter().list_check_in_items(user_id, bound, limit, scope)

  def list_injury_items(user_id, bound, limit, scope),
    do: adapter().list_injury_items(user_id, bound, limit, scope)

  def set_injury_visibility(id, user_id, rung),
    do: adapter().set_injury_visibility(id, user_id, rung)

  def list_check_ins_between(user_id, from, to),
    do: adapter().list_check_ins_between(user_id, from, to)

  def list_coach_visible_check_ins(user_id, organization_id),
    do: adapter().list_coach_visible_check_ins(user_id, organization_id)

  defp adapter, do: Application.fetch_env!(:palee, :wellbeing_store)
end
