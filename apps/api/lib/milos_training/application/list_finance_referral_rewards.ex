defmodule MilosTraining.Application.ListFinanceReferralRewards do
  alias MilosTraining.{Finance, Identity}

  def call do
    rewards = Finance.list_referral_rewards()
    events = Finance.list_referral_events()
    event_map = Map.new(events, &{&1.id, &1})
    programs = Finance.list_referral_programs() |> Map.new(&{&1.id, &1})
    users = user_map(rewards, events)

    {:ok,
     %{
       referral_rewards: Enum.map(rewards, &enrich_reward(&1, event_map, programs, users))
     }}
  end

  defp enrich_reward(reward, event_map, programs, users) do
    event = Map.get(event_map, reward.referral_event_id, %{})
    program = Map.get(programs, Map.get(event, :referral_program_id), %{})
    recipient = Map.get(users, reward.recipient_user_id, %{})
    referrer = Map.get(users, Map.get(event, :referrer_user_id), %{})
    referred = Map.get(users, Map.get(event, :referred_user_id), %{})

    reward
    |> Map.put(:program_name, Map.get(program, :name))
    |> Map.put(:recipient_nickname, Map.get(recipient, :nickname))
    |> Map.put(:referrer_nickname, Map.get(referrer, :nickname))
    |> Map.put(:referred_nickname, Map.get(referred, :nickname))
    |> Map.put(:referral_label, event_label(event, referrer, referred))
  end

  defp event_label(event, referrer, referred) do
    "#{Map.get(referrer, :nickname, short_id(Map.get(event, :referrer_user_id)))} -> #{Map.get(referred, :nickname, short_id(Map.get(event, :referred_user_id)))}"
  end

  defp user_map(rewards, events) do
    reward_user_ids = Enum.map(rewards, & &1.recipient_user_id)
    event_user_ids = Enum.flat_map(events, &[&1.referrer_user_id, &1.referred_user_id])

    (reward_user_ids ++ event_user_ids)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, %{nickname: &1.nickname, role: to_string(&1.role)}})
  end

  defp short_id(nil), do: "Unknown"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)
end
