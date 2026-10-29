defmodule Palee.Payments.Domain.TenantDataPolicy do
  @moduledoc """
  Online payments tenant data retention and purge policy (ADR-117,
  ADR-246/247).

  Payments and refunds are accounting records (kept like Finance's).
  Saved cards are provider tokens with the payer's consent: they are
  deleted with the payer's account and never exported in full.
  """

  alias Palee.TenantData.Domain.RetentionReview

  @policy RetentionReview.normalize!(%{
            context: "payments",
            purge_order: 83,
            disposition: :retain,
            retain_years: 10,
            # Provider credentials and saved-card tokens never leave the database.
            excluded_columns: ["credentials", "token"],
            basis:
              "Online payments, refunds and the provider's notifications are accounting records with a statutory retention period; saved-card tokens and the business's provider credentials are secrets, encrypted at rest and purged with the tenant.",
            tables: [
              %{table: "payment_webhook_events"},
              %{table: "payment_refunds"},
              %{table: "payment_intents"},
              %{table: "payment_methods"},
              %{table: "payment_accounts"}
            ]
          })

  def policy, do: @policy
end
