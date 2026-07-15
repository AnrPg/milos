defmodule MilosTraining.Application.GetAdminUserIncidents do
  @moduledoc false

  alias MilosTraining.{Identity, Wellbeing}

  def call(user_id) do
    with %{} <- Identity.find_by_id(user_id) || {:error, :not_found} do
      incidents = Wellbeing.list_injuries_for_user(user_id) |> Enum.map(&serialize/1)

      {:ok,
       %{
         user_id: user_id,
         incidents: incidents,
         summary: %{
           total: length(incidents),
           active: Enum.count(incidents, &(&1.status == "active"))
         }
       }}
    end
  end

  defp serialize(report) do
    Map.take(report, [
      :id,
      :body_area,
      :severity,
      :status,
      :started_on,
      :healed_on,
      :description,
      :training_limitations,
      :tags,
      :visibility,
      :reported_by_role,
      :inserted_at
    ])
  end
end
