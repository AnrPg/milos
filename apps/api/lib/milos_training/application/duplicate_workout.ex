defmodule MilosTraining.Application.DuplicateWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Identity
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(context, id, opts) do
    do_call(context, id, opts)
  end

  def call(id, opts \\ []) do
    do_call(nil, id, opts)
  end

  defp do_call(context, id, opts) do
    title_suffix = resolve_title_suffix(context, opts)

    attrs = opts |> Keyword.take([:folder_id]) |> Map.new()

    with {:ok, draft} <- duplicate_workout(context, id, title_suffix, attrs) do
      broadcast_admin_refresh(context, "workout_duplicated", draft.id)
      {:ok, draft}
    end
  end

  defp resolve_title_suffix(context, opts) do
    cond do
      suffix = opts[:title_suffix] ->
        suffix

      assignment_id = opts[:assignment_id] ->
        case get_assigned_workout(context, assignment_id) do
          %{athlete_ids: [_ | _] = athlete_ids} ->
            athlete_ids
            |> Identity.list_by_ids()
            |> build_athlete_suffix()

          _ ->
            "(copy)"
        end

      slot_id = opts[:slot_id] ->
        case get_slot(context, slot_id) do
          %{scheduled_at: scheduled_at} when not is_nil(scheduled_at) ->
            "(class #{format_date(scheduled_at)})"

          _ ->
            "(copy)"
        end

      true ->
        "(copy)"
    end
  end

  defp build_athlete_suffix([]), do: "(copy)"
  defp build_athlete_suffix([user]), do: "(#{user.nickname})"
  defp build_athlete_suffix(users), do: "(#{Enum.map_join(users, ", ", & &1.nickname)})"

  defp format_date(%DateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_date(%NaiveDateTime{} = datetime), do: Calendar.strftime(datetime, "%Y-%m-%d %H:%M")
  defp format_date(%Date{} = date), do: Calendar.strftime(date, "%Y-%m-%d")
  defp format_date(date) when is_binary(date), do: date
  defp format_date(_), do: "unknown"

  defp broadcast_admin_refresh(%{organization_id: organization_id}, reason, draft_id) do
    admin_ids = MilosTraining.Organizations.list_staff_user_ids(organization_id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: reason,
      payload: %{draft_id: draft_id}
    )
  end

  defp broadcast_admin_refresh(_context, reason, draft_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: reason,
      payload: %{draft_id: draft_id}
    )
  end

  defp duplicate_workout(nil, id, title_suffix, attrs),
    do: Workouts.duplicate_workout(id, title_suffix, attrs)

  defp duplicate_workout(context, id, title_suffix, attrs),
    do: Workouts.duplicate_workout(context, id, title_suffix, attrs)

  defp get_assigned_workout(nil, assignment_id), do: Workouts.get_assigned_workout(assignment_id)

  defp get_assigned_workout(context, assignment_id),
    do: Workouts.get_assigned_workout(context, assignment_id)

  defp get_slot(nil, slot_id), do: Scheduling.get_slot(slot_id)
  defp get_slot(context, slot_id), do: Scheduling.get_slot(context, slot_id)
end
