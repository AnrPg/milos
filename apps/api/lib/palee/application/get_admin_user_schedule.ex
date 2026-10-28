defmodule Palee.Application.GetAdminUserSchedule do
  alias Palee.{Identity, Organizations, Scheduling, Workouts}

  # ADR-217: the schedule follows the person's client role in this gym
  # (athlete: assignments; member: classes and assignments), never the
  # account-wide `users.role`. Staff-only people have no client schedule.

  def call(context, user_id, start_date, end_date) do
    with %{} = found <- Identity.find_by_id(user_id) || {:error, :not_found},
         user = %{found | role: client_role(context, found)},
         {:ok, start_date} <- Date.from_iso8601(start_date),
         {:ok, end_date} <- Date.from_iso8601(end_date) do
      {:ok,
       %{
         user_id: user.id,
         role: user.role && to_string(user.role),
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

    classes =
      Scheduling.list_member_slots(context, id, start_at, end_at)
      |> Enum.map(&Map.put(&1, :kind, "class"))

    # ADR-125: members may also hold personal assignments and class variants.
    assignments =
      Workouts.list_assigned_workouts_for_athlete(context, id, start_date, end_date)
      |> Enum.map(&Map.put(&1, :kind, "assignment"))

    classes ++ assignments
  end

  defp items(_context, _user, _start_date, _end_date), do: []

  defp client_role(%{organization_id: organization_id} = context, user)
       when is_binary(organization_id),
       do: Organizations.client_role(context, user.id)

  defp client_role(_context, user), do: user.role
end
