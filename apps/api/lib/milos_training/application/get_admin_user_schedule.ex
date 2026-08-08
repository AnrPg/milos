defmodule MilosTraining.Application.GetAdminUserSchedule do
  alias MilosTraining.{Identity, Scheduling, Workouts}

  def call(context, user_id, start_date, end_date) do
    with %{} = user <- Identity.find_by_id(user_id) || {:error, :not_found},
         {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date) do
      {:ok,
       %{
         user_id: user.id,
         role: to_string(user.role),
         start_date: Date.to_iso8601(start_date),
         end_date: Date.to_iso8601(end_date),
         items: items(context, user, start_date, end_date)
       }}
    else
      {:error, :invalid_format} -> {:error, :invalid_date}
      error -> error
    end
  end

  def call(user_id, start_date, end_date), do: call(%{}, user_id, start_date, end_date)

  defp items(context, %{role: :athlete, id: id}, start_date, end_date) do
    Workouts.list_assigned_workouts_for_athlete(context, id, start_date, end_date)
    |> Enum.map(&Map.put(&1, :kind, "assignment"))
  end

  defp items(context, %{role: :member, id: id}, start_date, end_date) do
    start_at = DateTime.new!(start_date, ~T[00:00:00], "Etc/UTC")
    end_at = end_date |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")

    Scheduling.list_member_slots(context, id, start_at, end_at)
    |> Enum.map(&Map.put(&1, :kind, "class"))
  end

  defp items(_context, _user, _start_date, _end_date), do: []
end
