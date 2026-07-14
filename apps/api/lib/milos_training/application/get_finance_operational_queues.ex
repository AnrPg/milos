defmodule MilosTraining.Application.GetFinanceOperationalQueues do
  alias MilosTraining.{Finance, Identity}

  def call(params \\ %{}) do
    queues = Finance.operational_queues(params)
    users = user_map(queues)

    {:ok, %{queues: enrich_queues(queues, users)}}
  end

  defp enrich_queues(queues, users) do
    queues
    |> Map.update(
      :expiring_memberships,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, row.user_id) end)
    )
    |> Map.update(
      :pending_payments,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, Map.get(row, :user_id)) end)
    )
    |> Map.update(
      :pending_referral_rewards,
      [],
      &Enum.map(&1, fn row -> put_user_label(row, users, row.recipient_user_id) end)
    )
  end

  defp put_user_label(row, users, user_id) do
    user = Map.get(users, user_id)

    row
    |> Map.put(:nickname, user && Map.get(user, :nickname))
    |> Map.put(:user_label, (user && Map.get(user, :nickname)) || short_id(user_id))
  end

  defp user_map(queues) do
    queues
    |> Map.take([:expiring_memberships, :pending_payments, :pending_referral_rewards])
    |> Map.values()
    |> List.flatten()
    |> Enum.flat_map(fn row -> [Map.get(row, :user_id), Map.get(row, :recipient_user_id)] end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, %{nickname: &1.nickname, role: to_string(&1.role)}})
  end

  defp short_id(nil), do: "Unknown"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)
end
