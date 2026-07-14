defmodule MilosTraining.Finance.MembershipPayment do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "membership_payments" do
    field :membership_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :finance_invoice_id, :binary_id
    field :amount_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :paid_on, :date
    field :payment_method, :string, default: "cash"
    field :payment_status, :string, default: "paid"
    field :notes, :string
    field :params, :map, default: %{}

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
    |> validate_inclusion(:payment_method, ["cash", "bank_transfer", "card_manual", "other"])
    |> validate_inclusion(:payment_status, ["paid", "pending", "refunded", "failed", "waived"])
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
    |> foreign_key_constraint(:finance_invoice_id)
  end
end
