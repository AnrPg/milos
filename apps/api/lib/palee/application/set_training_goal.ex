defmodule Palee.Application.SetTrainingGoal do
  @moduledoc """
  Sets a person's weekly workout goal (ADR-216). The person sets their own;
  staff reach this only through `AuthorizeClientAccess` (`:manage_coaching`),
  so a coach sets it for a client they coach and an owner/admin with full
  coaching scope for any client of the box. When someone else changes it the
  person is told who and to what, and can always change it back.
  """

  alias Palee.Application.{GetTrainingGoal, InvalidateLandingPages}
  alias Palee.{Coaching, Gamification, Notifications}
  alias Palee.Gamification.Domain.WeeklyGoal

  def call(context, %{id: actor_id} = actor, member_id, params) do
    coaches? = actor_id != member_id and Coaching.coaches?(context, actor_id, member_id)
    role = WeeklyGoal.setter_role(actor_id, member_id, coaches?)

    attrs = %{
      user_id: member_id,
      kind: WeeklyGoal.kind(),
      target: field(params, :weekly_workout_target),
      set_by_id: actor_id,
      set_by_role: role,
      set_in_organization_id:
        if(role == "self", do: nil, else: Map.get(context, :organization_id))
    }

    with :ok <- GetTrainingGoal.reachable(context, member_id),
         {:ok, goal} <-
           Gamification.with_tenant_context(context, fn ->
             Gamification.put_training_goal(attrs)
           end) do
      InvalidateLandingPages.for_users([member_id])
      notify(role, member_id, goal, actor)
      {:ok, WeeklyGoal.present(goal)}
    end
  end

  defp notify("self", _member_id, _goal, _actor), do: :ok

  defp notify(role, member_id, goal, actor) do
    Notifications.process_event("training_goal_updated", %{
      user_id: member_id,
      target: goal.target,
      set_by_role: role,
      set_by_nickname: Map.get(actor, :nickname)
    })
  end

  defp field(params, key), do: Map.get(params, key) || Map.get(params, Atom.to_string(key))
end
