defmodule Palee.Repo.Migrations.TerminalWalkInsTipsSurcharges do
  @moduledoc """
  ADR-264: Tap to Pay for walk-ins' free sales, tips and card surcharges.

    * `payment_intents.tip_cents` / `surcharge_cents`: what the provider
      confirmed on top of the requested amount (the requested amount stays
      `amount_cents`, the base of the sale).
    * Finance money with no membership was the shop's only (ADR-190). A
      walk-in's free sale (`event` or `other` stream) and a card surcharge
      (`other`) may have none too; membership and package money always
      name their membership.
    * One live Finance payment per walk-in sale and per card surcharge
      (`source_type` + `source_id`, the payment intent): a retried
      fulfilment cannot record the money twice.
  """

  use Ecto.Migration

  @tables [
    finance_invoices: [:membership_id, :user_id],
    membership_payments: [:membership_id],
    finance_payment_reversals: [:membership_id, :user_id]
  ]

  def up do
    alter table(:payment_intents) do
      add :tip_cents, :integer, null: false, default: 0
      add :surcharge_cents, :integer, null: false, default: 0
    end

    create constraint(:payment_intents, :payment_intents_tip_surcharge_check,
             check: "tip_cents >= 0 AND surcharge_cents >= 0"
           )

    replace_member_checks("revenue_stream IN ('shop', 'event', 'other')")

    create unique_index(:membership_payments, [:source_type, :source_id],
             where: "source_type IN ('walk_in_sale', 'card_surcharge') AND deleted_at IS NULL",
             name: :membership_payments_terminal_source_index
           )
  end

  def down do
    drop index(:membership_payments, [:source_type, :source_id],
           name: :membership_payments_terminal_source_index
         )

    replace_member_checks("revenue_stream = 'shop'")

    drop constraint(:payment_intents, :payment_intents_tip_surcharge_check)

    alter table(:payment_intents) do
      remove :tip_cents
      remove :surcharge_cents
    end
  end

  defp replace_member_checks(memberless) do
    for {table, columns} <- @tables do
      check = Enum.map_join(columns, " AND ", &"#{&1} IS NOT NULL")

      drop constraint(table, :"#{table}_member_or_shop_check")

      create constraint(table, :"#{table}_member_or_shop_check",
               check: "(#{check}) OR #{memberless}"
             )
    end
  end
end
