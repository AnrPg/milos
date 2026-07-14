defmodule MilosTraining.Repo.Migrations.PreventDuplicateFinanceRenewalInvoices do
  use Ecto.Migration

  def change do
    create unique_index(
             :finance_invoices,
             [
               :membership_id,
               :membership_package_subscription_id,
               :service_period_start,
               :service_period_end
             ],
             name: :finance_renewal_invoices_period_unique_index,
             where:
               "invoice_type = 'renewal' AND status <> 'void' AND membership_package_subscription_id IS NOT NULL"
           )
  end
end
