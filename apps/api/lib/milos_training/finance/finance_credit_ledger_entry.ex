defmodule MilosTraining.Finance.FinanceCreditLedgerEntry do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_credit_ledger_entries" do
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :membership_payment_id, :binary_id
    field :finance_invoice_id, :binary_id
    field :finance_invoice_line_id, :binary_id
    field :referral_reward_id, :binary_id
    field :promotion_redemption_id, :binary_id
    field :reversed_credit_ledger_entry_id, :binary_id
    field :source_type, :string
    field :entry_type, :string
    field :amount_cents, :integer
    field :currency, :string, default: "EUR"
    field :occurred_on, :date
    field :occurred_at, :utc_datetime_usec
    field :description, :string
    field :created_by_id, :binary_id
    field :idempotency_key, :string
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(entry \\ %__MODULE__{}, params) do
    entry
    |> cast(params, [
      :membership_id,
      :user_id,
      :membership_payment_id,
      :finance_invoice_id,
      :finance_invoice_line_id,
      :referral_reward_id,
      :promotion_redemption_id,
      :reversed_credit_ledger_entry_id,
      :source_type,
      :entry_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :description,
      :created_by_id,
      :idempotency_key,
      :params
    ])
    |> validate_required([
      :membership_id,
      :user_id,
      :source_type,
      :entry_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at
    ])
    |> validate_inclusion(:source_type, [
      "referral_reward",
      "manual_credit",
      "promo_credit",
      "payment_application",
      "reversal",
      "invoice_offset"
    ])
    |> validate_inclusion(:entry_type, ["grant", "application", "reversal", "invoice_offset"])
    |> validate_change(:amount_cents, fn
      :amount_cents, 0 -> [amount_cents: "must not be zero"]
      :amount_cents, _value -> []
    end)
    |> unique_constraint(:idempotency_key)
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:membership_payment_id)
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:finance_invoice_line_id)
    |> foreign_key_constraint(:referral_reward_id)
    |> foreign_key_constraint(:promotion_redemption_id)
    |> foreign_key_constraint(:reversed_credit_ledger_entry_id)
    |> foreign_key_constraint(:created_by_id)
  end
end
