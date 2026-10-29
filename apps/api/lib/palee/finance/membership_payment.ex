defmodule Palee.Finance.MembershipPayment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_payments" do
    field :organization_id, :binary_id, read_after_writes: true
    field :membership_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :finance_invoice_id, :binary_id
    field :amount_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :paid_on, :date
    field :payment_method, :string, default: "cash"
    field :payment_status, :string, default: "paid"
    field :notes, :string
    field :deleted_at, :utc_datetime_usec
    field :deleted_by_id, :binary_id
    field :deletion_reason, :string
    field :params, :map, default: %{}
    # ADR-190: revenue stream and the row that caused the payment.
    field :revenue_stream, :string, default: "membership"
    field :source_type, :string
    field :source_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(payment \\ %__MODULE__{}, params) do
    payment
    |> cast(params, [
      :membership_id,
      :membership_package_subscription_id,
      :finance_invoice_id,
      :amount_cents,
      :currency,
      :paid_on,
      :payment_method,
      :payment_status,
      :notes,
      :deleted_at,
      :deleted_by_id,
      :deletion_reason,
      :params
    ])
    |> validate_required([
      :membership_id,
      :amount_cents,
      :currency,
      :payment_method,
      :payment_status
    ])
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:payment_method, [
      "cash",
      "bank_transfer",
      "card_manual",
      "card_terminal",
      "online",
      "other"
    ])
    |> validate_inclusion(:payment_status, ["paid", "pending", "refunded", "failed", "waived"])
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
    |> foreign_key_constraint(:finance_invoice_id)
  end

  @doc """
  ADR-190: a payment written by a revenue stream, with its source row. One
  live payment per shop order (`membership_payments_shop_order_index`).
  """
  def stream_changeset(payment \\ %__MODULE__{}, params) do
    payment
    |> cast(params, [
      :membership_id,
      :finance_invoice_id,
      :amount_cents,
      :currency,
      :paid_on,
      :payment_method,
      :payment_status,
      :notes,
      :params,
      :revenue_stream,
      :source_type,
      :source_id
    ])
    |> validate_required([
      :amount_cents,
      :currency,
      :payment_method,
      :payment_status,
      :revenue_stream,
      :source_type,
      :source_id
    ])
    |> validate_number(:amount_cents, greater_than_or_equal_to: 0)
    |> validate_inclusion(:payment_method, [
      "cash",
      "bank_transfer",
      "card_manual",
      "card_terminal",
      "online",
      "other"
    ])
    |> validate_inclusion(:payment_status, ["paid", "pending", "refunded", "failed", "waived"])
    |> validate_inclusion(:revenue_stream, Palee.Finance.Domain.RevenueStream.keys())
    |> check_constraint(:membership_id, name: :membership_payments_member_or_shop_check)
    |> unique_constraint(:source_id, name: :membership_payments_shop_order_index)
    |> unique_constraint(:source_id, name: :membership_payments_terminal_source_index)
    |> foreign_key_constraint(:finance_invoice_id)
  end
end
