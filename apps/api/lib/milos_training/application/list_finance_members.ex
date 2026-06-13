defmodule MilosTraining.Application.ListFinanceMembers do
  alias MilosTraining.{Finance, Identity}

  def call(params \\ %{}) do
    limit = parse_limit(params["limit"] || params[:limit])

    users =
      Identity.list_all_users()
      |> Enum.reject(&(&1.role == :admin))

    user_ids = Enum.map(users, & &1.id)

    finance_summaries =
      Finance.search_member_summaries(%{
        user_ids: user_ids,
        limit: length(user_ids)
      })

    referrals_made =
      Finance.list_referral_events()
      |> Enum.group_by(& &1.referrer_user_id)

    members =
      users
      |> Enum.map(&build_row(&1, finance_summaries, referrals_made))
      |> Enum.take(limit)

    {:ok, %{members: members, meta: %{total: length(users), limit: limit}}}
  end

  defp build_row(user, finance_summaries, referrals_made) do
    profile = Map.get(finance_summaries, user.id)
    membership = if profile, do: profile.membership, else: nil
    active_sub = if profile, do: profile.active_package_subscription, else: nil

    made =
      referrals_made
      |> Map.get(user.id, [])
      |> Enum.map(& &1.referred_user_id)

    %{
      id: user.id,
      nickname: user.nickname,
      identity_role: to_string(user.role),
      membership: membership,
      active_package_subscription: active_sub,
      referrals_made_user_ids: made,
      last_payment_on: profile && Map.get(profile, :last_payment_on),
      last_payment_amount_cents: profile && Map.get(profile, :last_payment_amount_cents),
      notes: membership && Map.get(membership, :notes)
    }
  end

  defp parse_limit(nil), do: 5_000

  defp parse_limit(v) when is_binary(v),
    do: v |> Integer.parse() |> elem(0) |> min(5_000) |> max(1)

  defp parse_limit(v) when is_integer(v), do: min(v, 5_000) |> max(1)
end
