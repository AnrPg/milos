defmodule MilosTraining.Application.CreateFinanceReferralEvent do
  alias MilosTraining.Application.RecordAnalyticsEvent
  alias MilosTraining.{Finance, Identity}

  def call(params) do
    with {:ok, params} <- enrich_referral_participants(params),
         {:ok, event} <- Finance.create_referral_event(params) do
      RecordAnalyticsEvent.call_unsafe("referral_event_created", %{
        user_id: event.referred_user_id,
        context_type: "referral_event",
        context_id: event.id,
        metadata: %{
          referral_program_id: event.referral_program_id,
          referrer_user_id: event.referrer_user_id,
          membership_id: event.membership_id,
          status: event.status
        }
      })

      {:ok, event}
    end
  end

  defp enrich_referral_participants(params) do
    params = string_key_map(params)

    with {:ok, referrer} <- get_user(params["referrer_user_id"]),
         {:ok, referred} <- get_user(params["referred_user_id"]) do
      {:ok,
       params
       |> Map.put("referrer_role_snapshot", to_string(referrer.role))
       |> Map.put("referred_role_snapshot", to_string(referred.role))}
    end
  end

  defp get_user(nil), do: {:error, :referral_user_not_found}
  defp get_user(""), do: {:error, :referral_user_not_found}

  defp get_user(user_id) do
    case Identity.find_by_id(user_id) do
      nil -> {:error, :referral_user_not_found}
      user -> {:ok, user}
    end
  end

  defp string_key_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {to_string(key), value} end)
  end
end
