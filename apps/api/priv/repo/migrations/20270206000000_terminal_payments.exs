defmodule Palee.Repo.Migrations.TerminalPayments do
  @moduledoc """
  ADR-249: Tap to Pay at the desk through the Viva.com Terminal app.

    * payment intents learn `initiation = 'terminal'` and the purpose
      `free_sale` (a desk sale with a description, for a member);
    * membership and corporate payments learn the method `card_terminal`
      (a card-present payment Palee confirmed with the provider; never
      recorded by hand).
  """

  use Ecto.Migration

  @old_initiations "'payer', 'merchant'"
  @new_initiations "'payer', 'merchant', 'terminal'"
  @old_purposes "'finance_invoice', 'membership_package', 'shop_order', 'booking'"
  @new_purposes "'finance_invoice', 'membership_package', 'shop_order', 'booking', 'free_sale'"
  @old_methods "'cash', 'bank_transfer', 'card_manual', 'online', 'other'"
  @new_methods "'cash', 'bank_transfer', 'card_manual', 'card_terminal', 'online', 'other'"

  def up do
    replace_intent_check(@new_initiations, @new_purposes)
    replace_method_check(@new_methods)
  end

  def down do
    replace_method_check(@old_methods)
    replace_intent_check(@old_initiations, @old_purposes)
  end

  defp replace_intent_check(initiations, purposes) do
    drop constraint(:payment_intents, :payment_intents_check)

    create constraint(:payment_intents, :payment_intents_check,
             check: """
             provider IN ('sandbox', 'viva', 'stripe')
             AND environment IN ('test', 'live')
             AND initiation IN (#{initiations})
             AND purpose_type IN (#{purposes})
             AND status IN ('scheduled', 'awaiting_payer', 'processing', 'succeeded', 'failed',
                            'cancelled', 'expired')
             AND currency IN ('EUR', 'GBP', 'USD', 'CHF')
             AND amount_cents > 0
             AND refunded_cents >= 0 AND refunded_cents <= amount_cents
             AND attempts >= 0 AND fulfilment_attempts >= 0
             AND fulfilment_status IN ('none', 'pending', 'done', 'failed')
             AND (status <> 'succeeded' OR (succeeded_at IS NOT NULL AND provider_transaction_id IS NOT NULL))
             AND (initiation <> 'merchant' OR payment_method_id IS NOT NULL)
             AND (NOT save_method OR consent IS NOT NULL)
             """
           )
  end

  defp replace_method_check(methods) do
    for {table, name} <- [
          membership_payments: :membership_payments_method_check,
          finance_corporate_payments: :finance_corporate_payments_method
        ] do
      drop constraint(table, name)
      create constraint(table, name, check: "payment_method IN (#{methods})")
    end
  end
end
