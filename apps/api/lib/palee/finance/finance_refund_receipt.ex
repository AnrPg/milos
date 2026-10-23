defmodule Palee.Finance.FinanceRefundReceipt do
  @moduledoc """
  Immutable refund receipt issued for a payment reversal fact (ADR-126).

  There is deliberately no update changeset: the table rejects changes to
  every accounting column (`finance_refund_receipts_immutable` trigger).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_refund_receipts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :finance_payment_reversal_id, :binary_id
    field :membership_payment_id, :binary_id
    field :finance_invoice_id, :binary_id
    field :membership_id, :binary_id
    field :user_id, :binary_id
    # ADR-190: copied from the reversal by trigger; a shop receipt may name no membership.
    field :revenue_stream, :string, default: "membership", read_after_writes: true
    field :sequence, :integer
    field :receipt_number, :string
    field :reversal_type, :string
    field :amount_cents, :integer
    field :currency, :string
    field :reason, :string
    field :issued_by_id, :binary_id
    field :reversal_occurred_at, :utc_datetime_usec
    field :issued_at, :utc_datetime_usec
    field :schema_version, :integer, default: 1
    field :snapshot, :map
    field :snapshot_sha256, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @fields [
    :finance_payment_reversal_id,
    :membership_payment_id,
    :finance_invoice_id,
    :membership_id,
    :user_id,
    :sequence,
    :receipt_number,
    :reversal_type,
    :amount_cents,
    :currency,
    :reason,
    :issued_by_id,
    :reversal_occurred_at,
    :issued_at,
    :schema_version,
    :snapshot,
    :snapshot_sha256
  ]

  @required @fields -- [:finance_invoice_id, :membership_id, :reason, :issued_by_id]

  def create_changeset(params) do
    %__MODULE__{}
    |> cast(params, @fields)
    |> validate_required(@required)
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_number(:sequence, greater_than: 0)
    |> unique_constraint(:finance_payment_reversal_id,
      name: :finance_refund_receipts_reversal_index
    )
    |> unique_constraint([:organization_id, :sequence],
      name: :finance_refund_receipts_organization_sequence_index
    )
    |> unique_constraint([:organization_id, :receipt_number],
      name: :finance_refund_receipts_organization_number_index
    )
    |> foreign_key_constraint(:finance_payment_reversal_id)
    |> foreign_key_constraint(:membership_payment_id)
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:issued_by_id)
    |> check_constraint(:membership_id, name: :finance_refund_receipts_member_or_shop_check)
  end
end
