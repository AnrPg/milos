defmodule MilosTraining.Finance.FinanceReconciliationRecord do
  @moduledoc """
  One external payment-provider statement line and its (optional) match to an
  internal payment or reversal fact (ADR-126). Idempotent on
  `(organization_id, provider, external_reference)`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_reconciliation_records" do
    field :organization_id, :binary_id, read_after_writes: true
    field :provider, :string
    field :external_reference, :string
    field :external_type, :string
    field :external_status, :string, default: "settled"
    field :statement_amount_cents, :integer
    field :statement_currency, :string
    field :statement_occurred_on, :date
    field :statement_description, :string
    field :status, :string, default: "unmatched"
    field :membership_payment_id, :binary_id
    field :finance_payment_reversal_id, :binary_id
    field :discrepancies, {:array, :string}, default: []
    field :discrepancy_notes, :string
    field :matched_at, :utc_datetime_usec
    field :matched_by_id, :binary_id
    field :recorded_by_id, :binary_id
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :provider,
      :external_reference,
      :external_type,
      :external_status,
      :statement_amount_cents,
      :statement_currency,
      :statement_occurred_on,
      :statement_description,
      :recorded_by_id,
      :params
    ])
    |> validate_required([
      :provider,
      :external_reference,
      :external_type,
      :external_status,
      :statement_amount_cents,
      :statement_currency,
      :statement_occurred_on
    ])
    |> validate_inclusion(:external_type, ["payment", "refund"])
    |> validate_inclusion(:external_status, ["settled", "pending", "failed"])
    |> validate_number(:statement_amount_cents, greater_than: 0)
    |> unique_constraint([:organization_id, :provider, :external_reference],
      name: :finance_reconciliation_records_external_index
    )
    |> foreign_key_constraint(:recorded_by_id)
  end

  def match_changeset(%__MODULE__{} = record, params) do
    record
    |> cast(params, [
      :status,
      :membership_payment_id,
      :finance_payment_reversal_id,
      :discrepancies,
      :discrepancy_notes,
      :matched_at,
      :matched_by_id
    ])
    |> validate_inclusion(:status, ["unmatched", "matched", "mismatched"])
    |> unique_constraint([:organization_id, :membership_payment_id],
      name: :finance_reconciliation_records_payment_index
    )
    |> unique_constraint([:organization_id, :finance_payment_reversal_id],
      name: :finance_reconciliation_records_reversal_index
    )
    |> check_constraint(:membership_payment_id,
      name: :finance_reconciliation_single_target_check
    )
    |> foreign_key_constraint(:membership_payment_id)
    |> foreign_key_constraint(:finance_payment_reversal_id)
    |> foreign_key_constraint(:matched_by_id)
  end
end
