defmodule MilosTraining.Application.GetAssignedWorkoutWeek do
  alias MilosTraining.{Identity, Workouts}

  def call(user, params \\ %{}) do
    with {:ok, start_date} <- parse_start_date(params) do
      end_date = Date.add(start_date, 6)

      assignments =
        case user.role do
          :admin ->
            Workouts.list_assigned_workouts_for_admin(start_date, end_date)
            |> attach_athletes()

          :athlete ->
            Workouts.list_assigned_workouts_for_athlete(user.id, start_date, end_date)
            |> strip_admin_fields()
        end

      {:ok,
       %{
         start_date: Date.to_iso8601(start_date),
         end_date: Date.to_iso8601(end_date),
         assignments: assignments
       }}
    end
  end

  defp parse_start_date(params) do
    case Map.get(params, "start_date") || Map.get(params, :start_date) do
      nil ->
        {:ok, Date.utc_today() |> Date.beginning_of_week(:monday)}

      "" ->
        {:ok, Date.utc_today() |> Date.beginning_of_week(:monday)}

      value ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> {:error, :bad_request}
        end
    end
  end

  defp attach_athletes(assignments) do
    athletes_by_id =
      assignments
      |> Enum.flat_map(&Map.get(&1, :athlete_ids, []))
      |> Enum.uniq()
      |> Identity.list_by_ids()
      |> Map.new(&{&1.id, %{id: &1.id, nickname: &1.nickname, role: to_string(&1.role)}})

    Enum.map(assignments, fn assignment ->
      athletes =
        assignment
        |> Map.get(:athlete_ids, [])
        |> Enum.map(&Map.get(athletes_by_id, &1))
        |> Enum.reject(&is_nil/1)

      Map.put(assignment, :athletes, athletes)
    end)
  end

  defp strip_admin_fields(assignments) do
    Enum.map(assignments, &Map.drop(&1, [:athlete_ids]))
  end
end
