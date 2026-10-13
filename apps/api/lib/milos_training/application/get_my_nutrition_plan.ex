defmodule MilosTraining.Application.GetMyNutritionPlan do
  @moduledoc "The client's nutrition plan, when their package includes one (ADR-098)."

  alias MilosTraining.Application.AuthorizePackageFeature
  alias MilosTraining.Nutrition

  def call(context, actor) do
    with :ok <- AuthorizePackageFeature.call(context, actor, :receive_nutrition_plan) do
      {:ok, Nutrition.get_plan(context, actor.id)}
    end
  end
end
