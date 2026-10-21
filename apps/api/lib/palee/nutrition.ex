defmodule Palee.Nutrition do
  @moduledoc """
  Nutrition context (ADR-098): one current plan per client, written by staff.
  Clients read it through `Application.GetMyNutritionPlan`, which checks the
  package. Daily hand portions and meal slots (ADR-159) are what the member
  sees of the plan's numbers; calories stay with the staff.
  """

  alias Palee.Nutrition.Domain.PortionPolicy
  alias Palee.Nutrition.NutritionStore

  def get_plan(context, user_id), do: NutritionStore.get_plan(context, user_id)
  def put_plan(context, user_id, params), do: NutritionStore.put_plan(context, user_id, params)
  def delete_plan(context, user_id), do: NutritionStore.delete_plan(context, user_id)

  # ADR-159: hand portions and meal slots.
  defdelegate portion_keys(), to: PortionPolicy, as: :keys
  defdelegate meal_slots(), to: PortionPolicy, as: :slots
  defdelegate default_meal_slots(), to: PortionPolicy, as: :default_slots
  defdelegate effective_portions(plan), to: PortionPolicy, as: :effective
  defdelegate logged_portions(meal_values), to: PortionPolicy, as: :logged

  @doc "The member's own plans across their gyms, newest first (no calories, no text)."
  def list_own_plans(context), do: NutritionStore.list_own_plans(context)

  @doc "A plan as the member may see it: never calories (board 14, Q5)."
  def for_member(nil), do: nil

  def for_member(plan),
    do: plan |> Map.delete(:daily_calories) |> Map.put(:portions, PortionPolicy.effective(plan))

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: Palee.Nutrition.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: Palee.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: Palee.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: Palee.TenantData.TableStore.purge(tenant_data_policy(), context)
end
