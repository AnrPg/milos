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
end
