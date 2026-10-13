defmodule MilosTraining.Infrastructure.Nutrition.EctoNutritionStore do
  @moduledoc "Ecto adapter of the Nutrition store (ADR-098)."

  @behaviour MilosTraining.Nutrition.Ports.NutritionStore

  import Ecto.Query

  alias MilosTraining.Nutrition.Plan
  alias MilosTraining.Repo

  @impl true
  def get_plan(%{organization_id: organization_id}, user_id) do
    case fetch(organization_id, user_id) do
      nil -> nil
      plan -> normalize(plan)
    end
  end

  @impl true
  def put_plan(%{organization_id: organization_id}, user_id, params) do
    params =
      params
      |> Map.new(fn {key, value} -> {to_string(key), value} end)
      |> Map.merge(%{"organization_id" => organization_id, "user_id" => user_id})

    (fetch(organization_id, user_id) || %Plan{})
    |> Plan.changeset(params)
    |> Repo.insert_or_update()
    |> case do
      {:ok, plan} -> {:ok, normalize(plan)}
      error -> error
    end
  end

  @impl true
  def delete_plan(%{organization_id: organization_id}, user_id) do
    Plan
    |> where([plan], plan.organization_id == ^organization_id and plan.user_id == ^user_id)
    |> Repo.delete_all()

    :ok
  end

  defp fetch(organization_id, user_id),
    do: Repo.get_by(Plan, organization_id: organization_id, user_id: user_id)

  defp normalize(%Plan{} = plan) do
    Map.take(plan, [
      :id,
      :user_id,
      :title,
      :body,
      :daily_calories,
      :protein_grams,
      :carbs_grams,
      :fat_grams,
      :updated_by_id,
      :inserted_at,
      :updated_at
    ])
  end
end
