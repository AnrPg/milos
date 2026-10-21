defmodule Palee.Repo.Migrations.ReferralDiscountRenewals do
  use Ecto.Migration

  # ADR-156 (board 11 Q6 extra): «Δόθηκε» on a discount reward takes it off
  # the member's next renewal invoice. The reward remembers the invoice that
  # used it, so it is used once; voiding that invoice frees it again.

  def change do
    alter table(:referral_rewards) do
      add :renewal_invoice_id,
          references(:finance_invoices, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:referral_rewards, [:recipient_user_id],
             where:
               "reward_type = 'discount' AND status = 'applied' AND renewal_invoice_id IS NULL",
             name: :referral_rewards_open_discounts_index
           )

    create index(:referral_rewards, [:renewal_invoice_id],
             where: "renewal_invoice_id IS NOT NULL"
           )
  end
end
