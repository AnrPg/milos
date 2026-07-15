defmodule MilosTraining.Application.GetMyFinance do
  alias MilosTraining.Finance

  @non_draft_statuses ~w[issued partially_paid paid overdue void]
  @outstanding_statuses ~w[issued partially_paid overdue]

  def call(user_id) do
    packages = Finance.list_packages()

    case Finance.get_member_profile(user_id) do
      nil ->
        {:ok,
         %{
           membership: nil,
           active_package_subscription: nil,
           invoices: [],
           payments: [],
           credit_balance: 0,
           total_outstanding_balance_cents: 0,
           referral_credits: [],
           promotion_redemptions: [],
           available_packages: packages,
           effective_entitlement: nil
         }}

      profile ->
        visible_invoices = Enum.filter(profile.invoices, &(&1.status in @non_draft_statuses))
        invoice_ids = Enum.map(visible_invoices, & &1.id)
        balance_due_map = Finance.invoice_balance_due_map(invoice_ids)

        enriched_invoices =
          Enum.map(visible_invoices, fn invoice ->
            balance_due_cents = Map.get(balance_due_map, invoice.id, 0)
            Map.put(invoice, :balance_due_cents, balance_due_cents)
          end)

        total_outstanding =
          enriched_invoices
          |> Enum.filter(&(&1.status in @outstanding_statuses))
          |> Enum.reduce(0, fn inv, acc -> acc + Map.get(inv, :balance_due_cents, 0) end)

        {:ok,
         %{
           membership: profile.membership,
           active_package_subscription: profile.active_package_subscription,
           invoices: enriched_invoices,
           payments: profile.payments,
           credit_balance: profile.credit_balance,
           total_outstanding_balance_cents: total_outstanding,
           referral_credits:
             Enum.filter(profile.credit_ledger_entries, &(&1.referral_reward_id != nil)),
           promotion_redemptions: profile.promotion_redemptions,
           available_packages: packages,
           effective_entitlement: Finance.get_effective_entitlement(user_id)
         }}
    end
  end
end
