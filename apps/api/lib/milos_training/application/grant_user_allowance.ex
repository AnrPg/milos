defmodule MilosTraining.Application.GrantUserAllowance do
  alias MilosTraining.Application.BroadcastUserSync
  alias MilosTraining.{Finance, Identity}

  def call(user_id, admin_id, params) do
    with %{role: role} when role in [:member, :athlete] <- Identity.find_by_id(user_id),
         {:ok, entry} <- Finance.grant_allowance(user_id, admin_id, normalize(params)),
         entitlement when not is_nil(entitlement) <- Finance.get_effective_entitlement(user_id) do
      BroadcastUserSync.for_user(user_id, ["finance_entitlement"],
        reason: "allowance_extended",
        payload: %{allowance: entry.allowance_key, quantity: abs(entry.quantity_delta)}
      )

      {:ok, %{entry: entry, entitlement: entitlement}}
    else
      nil -> {:error, :not_found}
      %{role: _role} -> {:error, :finance_profile_ineligible}
      error -> error
    end
  end

  defp normalize(params) do
    params = Map.new(params, fn {key, value} -> {normalize_key(key), value} end)

    params
    |> Map.update(:allowance, nil, &normalize_allowance/1)
    |> Map.update(:period, nil, &normalize_period/1)
    |> Map.update(:occurred_on, Date.utc_today(), &normalize_date/1)
    |> Map.put_new(:idempotency_key, "admin-allowance:#{Ecto.UUID.generate()}")
  end

  defp normalize_key(key) when is_atom(key), do: key

  defp normalize_key(key) when is_binary(key) do
    case key do
      "allowance" -> :allowance
      "quantity" -> :quantity
      "period" -> :period
      "occurred_on" -> :occurred_on
      "reason" -> :reason
      "idempotency_key" -> :idempotency_key
      _ -> key
    end
  end

  defp normalize_allowance("class_visits"), do: :class_visits
  defp normalize_allowance("coaching_touchpoints"), do: :coaching_touchpoints
  defp normalize_allowance(value), do: value

  defp normalize_period("calendar_week"), do: :calendar_week
  defp normalize_period("calendar_month"), do: :calendar_month
  defp normalize_period("subscription_period"), do: :subscription_period
  defp normalize_period(value), do: value

  defp normalize_date(%Date{} = date), do: date

  defp normalize_date(value) when is_binary(value) do
    case Date.from_iso8601(value) do
      {:ok, date} -> date
      _ -> value
    end
  end

  defp normalize_date(value), do: value
end
