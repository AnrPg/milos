defmodule Palee.Shop.Order do
  @moduledoc """
  A shop order (ADR-190): a member's online order for pickup at a branch, or
  a desk (POS) sale to a member or a walk-in. Fulfilment (`status`) and money
  (`payment_status`) move independently, so "pay at pickup" works: an order
  can be ready for pickup while its payment is still pending.
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Palee.Shop.Domain.OrderLifecycle

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "shop_orders" do
    field :organization_id, :binary_id, read_after_writes: true
    field :number, :integer
    field :channel, Ecto.Enum, values: OrderLifecycle.channels()
    field :status, Ecto.Enum, values: OrderLifecycle.statuses(), default: :placed

    field :payment_status, Ecto.Enum,
      values: OrderLifecycle.payment_statuses(),
      default: :pending_payment

    field :payment_mode, Ecto.Enum, values: OrderLifecycle.payment_modes()
    field :user_id, :binary_id
    field :membership_id, :binary_id
    field :customer_name, :string
    field :pickup_location_id, :binary_id
    field :currency, :string, default: "EUR"
    field :subtotal_cents, :integer, default: 0
    field :discount_cents, :integer, default: 0
    field :total_cents, :integer, default: 0
    field :paid_cents, :integer, default: 0
    field :refunded_cents, :integer, default: 0
    field :source, Ecto.Enum, values: OrderLifecycle.sources(), default: :direct
    field :source_ref_id, :binary_id
    field :promotion_code, :string
    field :finance_invoice_id, :binary_id
    field :fiscal_receipt_ref, :string
    field :payment_provider, :string
    field :payment_reference, :string
    field :note, :string
    field :idempotency_key, :string
    field :payment_idempotency_key, :string
    field :placed_at, :utc_datetime_usec
    field :expires_at, :utc_datetime_usec
    field :paid_at, :utc_datetime_usec
    field :ready_at, :utc_datetime_usec
    field :picked_up_at, :utc_datetime_usec
    field :cancelled_at, :utc_datetime_usec
    field :cancel_reason, :string
    field :created_by_id, :binary_id
    field :handled_by_id, :binary_id

    has_many :lines, Palee.Shop.OrderLine, foreign_key: :order_id

    timestamps(type: :utc_datetime_usec)
  end

  @create_fields [
    :number,
    :channel,
    :status,
    :payment_status,
    :payment_mode,
    :user_id,
    :membership_id,
    :customer_name,
    :pickup_location_id,
    :currency,
    :subtotal_cents,
    :discount_cents,
    :total_cents,
    :source,
    :source_ref_id,
    :promotion_code,
    :note,
    :idempotency_key,
    :placed_at,
    :expires_at,
    :created_by_id
  ]

  @update_fields [
    :status,
    :payment_status,
    :paid_cents,
    :refunded_cents,
    :finance_invoice_id,
    :fiscal_receipt_ref,
    :payment_provider,
    :payment_reference,
    :payment_idempotency_key,
    :paid_at,
    :ready_at,
    :picked_up_at,
    :cancelled_at,
    :cancel_reason,
    :handled_by_id,
    :payment_mode
  ]

  def create_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @create_fields)
    |> validate_required([
      :number,
      :channel,
      :payment_mode,
      :currency,
      :idempotency_key,
      :placed_at
    ])
    |> validate_length(:customer_name, max: 160)
    |> validate_length(:promotion_code, max: 64)
    |> validate_length(:note, max: 1000)
    |> validate_length(:idempotency_key, min: 8, max: 200)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> unique_constraint(:idempotency_key, name: :shop_orders_idempotency_index)
    |> unique_constraint(:number, name: :shop_orders_organization_number_index)
    |> check_constraint(:user_id, name: :shop_orders_online_buyer_check)
  end

  def update_changeset(order, attrs) do
    order
    |> cast(attrs, @update_fields)
    |> validate_length(:cancel_reason, max: 500)
    |> validate_length(:fiscal_receipt_ref, max: 120)
    |> check_constraint(:refunded_cents, name: :shop_orders_amounts_check)
  end
end
