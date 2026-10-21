defmodule MilosTraining.Nutrition.NutritionStore do
  @moduledoc false
  @behaviour MilosTraining.Nutrition.Ports.NutritionStore

  alias MilosTraining.Infrastructure.Tenancy.RepoContext

  defp adapter, do: Application.fetch_env!(:milos_training, :nutrition_store)

  defp tenant_call(context, function, args) do
    RepoContext.run(context, fn -> apply(adapter(), function, [context | args]) end)
  end

  @impl true
  def get_plan(context, user_id), do: tenant_call(context, :get_plan, [user_id])

  @impl true
  def put_plan(context, user_id, params), do: tenant_call(context, :put_plan, [user_id, params])

  @impl true
  def delete_plan(context, user_id), do: tenant_call(context, :delete_plan, [user_id])

  # The member's own plans in their personal session (ADR-159).
  def list_own_plans(context), do: RepoContext.run(context, fn -> adapter().list_own_plans() end)

  @impl true
  def list_own_plans, do: adapter().list_own_plans()
end
