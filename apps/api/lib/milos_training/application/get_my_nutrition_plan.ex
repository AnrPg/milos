defmodule MilosTraining.Application.GetMyNutritionPlan do
  @moduledoc """
  The client's nutrition plan, when their package includes one (ADR-098).
  Calories are the staff's working number and never reach the member;
  daily hand portions do (ADR-159, board 14 Q5).
  """

  alias MilosTraining.Application.AuthorizePackageFeature
  alias MilosTraining.Nutrition

  def call(context, actor) do
    with :ok <- AuthorizePackageFeature.call(context, actor, :receive_nutrition_plan) do
      {:ok, context |> Nutrition.get_plan(actor.id) |> Nutrition.for_member()}
    end
  end
end
