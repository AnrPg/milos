defmodule MilosTraining.Application.SaveNutritionPlan do
  @moduledoc "Staff write a client's nutrition plan; the client is notified (ADR-098)."

  alias MilosTraining.{Notifications, Nutrition, Organizations}

  def call(context, %{id: staff_id}, user_id, params) do
    with :ok <- client_of_gym(context, user_id),
         {:ok, plan} <-
           Nutrition.put_plan(context, user_id, Map.put(params, :updated_by_id, staff_id)) do
      Notifications.process_event("nutrition_plan_updated", %{
        user_id: user_id,
        title: plan.title
      })

      {:ok, plan}
    end
  end

  defp client_of_gym(%{organization_id: organization_id}, user_id) do
    if user_id in Organizations.list_active_membership_user_ids(organization_id),
      do: :ok,
      else: {:error, :not_found}
  end
end
