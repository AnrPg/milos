defmodule Palee.Application.GetFinanceMemberProfile do
  alias Palee.Finance
  alias Palee.Finance.Domain.MemberDrillDown
  alias Palee.Identity

  def call(user_id), do: call(user_id, nil)

  def call(user_id, tenant_context) do
    case Identity.find_by_id(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        profile =
          case get_member_profile(tenant_context, user_id) do
            nil -> empty_profile()
            profile -> profile
          end

        {:ok,
         Map.put(
           profile,
           :drill_down,
           MemberDrillDown.build(user, profile, today(tenant_context))
         )}
    end
  end

  defp get_member_profile(nil, user_id), do: Finance.get_member_profile(user_id)

  defp get_member_profile(tenant_context, user_id),
    do: Finance.get_member_profile(tenant_context, user_id)

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

  # ADR-177: the gym's day inside a gym; the UTC day for the vendor's view.
  defp today(%{organization_id: organization_id}) when is_binary(organization_id),
    do: Palee.Organizations.local_today(organization_id)

  defp today(_context), do: Date.utc_today()
end
