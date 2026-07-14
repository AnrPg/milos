defmodule MilosTraining.Application.UpdateUserRole do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Identity, Scheduling, Workouts}

  def call(user_id, params) when is_map(params) do
    role = normalize_role(Map.get(params, "role") || Map.get(params, :role))

    with {:ok, current_user} <- fetch_user(user_id),
         :ok <- reconcile_role_owned_state(current_user.role, role, user_id),
         {:ok, updated_user} <- Identity.update_role(user_id, role) do
      broadcast_role_change(updated_user)
      {:ok, updated_user}
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  defp fetch_user(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  defp reconcile_role_owned_state(role, role, _user_id), do: :ok

  defp reconcile_role_owned_state(:member, _new_role, user_id) do
    with {:ok, _booking_ids} <- Scheduling.cancel_active_future_bookings_for_user(user_id) do
      :ok
    end
  end

  defp reconcile_role_owned_state(:athlete, _new_role, user_id) do
    with {:ok, _assignment_ids} <- Workouts.archive_active_assignments_for_athlete(user_id) do
      :ok
    end
  end

  defp reconcile_role_owned_state(_role, _new_role, _user_id), do: :ok

  defp broadcast_role_change(user) do
    BroadcastUserSync.for_user(user.id, ["session"],
      reason: "role_changed",
      payload: %{role: to_string(user.role)}
    )

    admin_ids = Identity.list_by_role(:admin) |> Enum.map(& &1.id)

    BroadcastUserSync.for_users(admin_ids, ["admin_athletes", "admin_finance"],
      reason: "user_role_changed",
      payload: %{user_id: user.id, role: to_string(user.role)}
    )
  end

  defp normalize_role(role) when role in [:member, :athlete, :admin], do: role
  defp normalize_role("member"), do: :member
  defp normalize_role("athlete"), do: :athlete
  defp normalize_role("admin"), do: :admin
  defp normalize_role(role), do: role
end
