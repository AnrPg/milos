defmodule MilosTraining.Application.DuplicateWorkout do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.Identity
  alias MilosTraining.Scheduling
  alias MilosTraining.Workouts

  def call(id, opts \\ []) do
    title_suffix = resolve_title_suffix(opts)

    with {:ok, draft} <- Workouts.duplicate_workout(id, title_suffix) do
      broadcast_admin_refresh("workout_duplicated", draft.id)
      {:ok, draft}
    end
  end

  defp resolve_title_suffix(opts) do
    cond do
      assignment_id = opts[:assignment_id] ->
        case Workouts.get_assigned_workout(assignment_id) do
          %{athlete_ids: [_ | _] = athlete_ids} ->
            athlete_ids
            |> Identity.list_by_ids()
            |> build_athlete_suffix()

          _ ->
            "(copy)"
        end

      slot_id = opts[:slot_id] ->
        case Scheduling.get_slot(slot_id) do
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

  defp broadcast_admin_refresh(reason, draft_id) do
    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_workouts"],
      reason: reason,
      payload: %{draft_id: draft_id}
    )
  end
end
