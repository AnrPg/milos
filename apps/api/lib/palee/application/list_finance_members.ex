defmodule Palee.Application.ListFinanceMembers do
  alias Palee.{Finance, Identity, Organizations}

  # TD-092: the rows are the gym's own active members. The `users` table has no
  # RLS, so listing every account leaked the nickname and id of every user on
  # the platform to any gym's finance desk (their finance columns were merely
  # empty). The finance reads run in the caller's tenant scope (the controller
  # wraps each action in `Finance.with_tenant_context/2`).
  def call(context, params \\ %{}) do
    limit = parse_limit(params["limit"] || params[:limit])

    users =
      context
      |> Organizations.list_active_membership_user_ids()
      |> Identity.list_by_ids()
      |> Enum.reject(&(&1.role == :admin))
      |> Enum.sort_by(& &1.nickname)

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
      credit_balance: profile && Map.get(profile, :credit_balance),
      credit_balance_cents: profile && Map.get(profile, :credit_balance_cents),
      outstanding_balance_cents: profile && Map.get(profile, :outstanding_balance_cents, 0),
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
