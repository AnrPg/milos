defmodule Palee.Finance.FinancePaymentReversal do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_payment_reversals" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :membership_payment_id, :binary_id
    field :finance_invoice_id, :binary_id
    field :reversal_type, :string, default: "refund"
    field :amount_cents, :integer
    field :currency, :string, default: "EUR"
    field :occurred_on, :date
    field :occurred_at, :utc_datetime_usec
    field :reason, :string
    field :created_by_id, :binary_id
    field :idempotency_key, :string
    field :deleted_at, :utc_datetime_usec
    field :deleted_by_id, :binary_id
    field :deletion_reason, :string
    field :params, :map, default: %{}
    # ADR-190: inherited from the reversed payment (database trigger).
    field :revenue_stream, :string, default: "membership", read_after_writes: true
    field :source_type, :string, read_after_writes: true
    field :source_id, :binary_id, read_after_writes: true

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(reversal \\ %__MODULE__{}, params) do
    reversal
    |> cast(params, [
      :membership_id,
      :user_id,
      :membership_payment_id,
      :finance_invoice_id,
      :reversal_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :reason,
      :created_by_id,
      :idempotency_key,
      :deleted_at,
      :deleted_by_id,
      :deletion_reason,
      :params
    ])
    |> validate_required([
      :membership_id,
      :user_id,
      :membership_payment_id,
      :reversal_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :idempotency_key
    ])
    |> validate_inclusion(:reversal_type, ["refund", "payment_reversal", "waiver_reversal"])
    |> validate_number(:amount_cents, greater_than: 0)
    |> unique_constraint(:idempotency_key)
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:membership_payment_id)
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:created_by_id)
  end

  @doc """
  ADR-190: a reversal of a revenue-stream payment. The stream and source
  are copied from the payment by the database, whatever is passed here.
  """
  def stream_changeset(reversal \\ %__MODULE__{}, params) do
    reversal
    |> cast(params, [
      :membership_id,
      :user_id,
      :membership_payment_id,
      :finance_invoice_id,
      :reversal_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :reason,
      :created_by_id,
      :idempotency_key,
      :params
    ])
    |> validate_required([
      :membership_payment_id,
      :reversal_type,
      :amount_cents,
      :currency,
      :occurred_on,
      :occurred_at,
      :idempotency_key
    ])
    |> validate_inclusion(:reversal_type, ["refund", "payment_reversal"])
    |> validate_number(:amount_cents, greater_than: 0)
    |> check_constraint(:membership_id, name: :finance_payment_reversals_member_or_shop_check)
    |> unique_constraint(:idempotency_key)
    |> foreign_key_constraint(:membership_payment_id)
  end
end
