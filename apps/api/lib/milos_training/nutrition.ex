defmodule MilosTraining.Nutrition do
  @moduledoc """
  Nutrition context (ADR-098): one current plan per client, written by staff.
  Clients read it through `Application.GetMyNutritionPlan`, which checks the
  package.
  """

  alias MilosTraining.Nutrition.NutritionStore

  def get_plan(context, user_id), do: NutritionStore.get_plan(context, user_id)
  def put_plan(context, user_id, params), do: NutritionStore.put_plan(context, user_id, params)
  def delete_plan(context, user_id), do: NutritionStore.delete_plan(context, user_id)

  # Tenant data lifecycle (ADR-117).
  def tenant_data_policy, do: MilosTraining.Nutrition.Domain.TenantDataPolicy.policy()

  def tenant_data_inventory(context),
    do: MilosTraining.TenantData.TableStore.inventory(tenant_data_policy(), context)

  def export_tenant_data(context, mode \\ :full),
    do: MilosTraining.TenantData.TableStore.export(tenant_data_policy(), context, mode)

  def purge_tenant_data(context),
    do: MilosTraining.TenantData.TableStore.purge(tenant_data_policy(), context)
end
