defmodule Palee.PlatformPlans.PlanStore do
  @behaviour Palee.PlatformPlans.Ports.PlanStore

  @impl true
  def list_plans(filters), do: impl().list_plans(filters)
  @impl true
  def get_plan(code), do: impl().get_plan(code)
  @impl true
  def create_plan(attrs), do: impl().create_plan(attrs)
  @impl true
  def update_plan(code, attrs), do: impl().update_plan(code, attrs)
  @impl true
  def ensure_subscription(organization_id), do: impl().ensure_subscription(organization_id)
  @impl true
  def get_subscription(organization_id), do: impl().get_subscription(organization_id)
  @impl true
  def list_subscriptions(organization_ids), do: impl().list_subscriptions(organization_ids)
  @impl true
  def assign_subscription(organization_id, attrs),
    do: impl().assign_subscription(organization_id, attrs)

  defp impl,
    do:
      Application.get_env(
        :palee,
        :platform_plan_store,
        Palee.Infrastructure.PlatformPlans.EctoPlanStore
      )
end
