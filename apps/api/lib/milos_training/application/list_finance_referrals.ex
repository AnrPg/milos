defmodule MilosTraining.Application.ListFinanceReferrals do
  alias MilosTraining.{Finance, Identity}

  def call do
    events = Finance.list_referral_events()
    programs = program_map()
    users = user_map(events)

    {:ok, %{referral_events: Enum.map(events, &enrich_event(&1, programs, users))}}
  end

  defp enrich_event(event, programs, users) do
    program = Map.get(programs, event.referral_program_id, %{})
    referrer = Map.get(users, event.referrer_user_id, %{})
    referred = Map.get(users, event.referred_user_id, %{})

    event
    |> Map.put(:program_name, Map.get(program, :name))
    |> Map.put(:referrer_nickname, Map.get(referrer, :nickname))
    |> Map.put(:referred_nickname, Map.get(referred, :nickname))
    |> Map.put(:label, event_label(event, referrer, referred))
  end

  defp event_label(event, referrer, referred) do
    "#{Map.get(referrer, :nickname, short_id(event.referrer_user_id))} -> #{Map.get(referred, :nickname, short_id(event.referred_user_id))}"
  end

  defp program_map do
    Finance.list_referral_programs()
    |> Map.new(&{&1.id, &1})
  end

  defp user_map(events) do
    events
    |> Enum.flat_map(&[&1.referrer_user_id, &1.referred_user_id])
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Identity.list_by_ids()
    |> Map.new(&{&1.id, %{nickname: &1.nickname, role: to_string(&1.role)}})
  end

  defp short_id(nil), do: "Unknown"
  defp short_id(id), do: String.slice(to_string(id), 0, 8)
end
