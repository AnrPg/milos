defmodule MilosTraining.Application.GetFinanceMemberProfile do
  alias MilosTraining.Finance
  alias MilosTraining.Finance.Domain.MemberDrillDown
  alias MilosTraining.Identity

  def call(user_id) do
    case Identity.find_by_id(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        profile =
          case Finance.get_member_profile(user_id) do
            nil -> empty_profile()
            profile -> profile
          end

        {:ok, Map.put(profile, :drill_down, MemberDrillDown.build(user, profile))}
    end
  end

  defp empty_profile do
    %{
      membership: nil,
      package_subscriptions: [],
      active_package_subscription: nil,
      invoices: [],
      payments: [],
      payment_reversals: [],
      promotion_redemptions: [],
      credit_ledger_entries: [],
      credit_balance: 0,
      entitlement: nil
    }
  end
end
