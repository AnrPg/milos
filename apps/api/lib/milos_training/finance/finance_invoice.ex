defmodule MilosTraining.Finance.FinanceInvoice do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_invoices" do
    field :membership_id, :binary_id
    field :user_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :invoice_number, :string
    field :invoice_type, :string, default: "manual"
    field :status, :string, default: "draft"
    field :issue_date, :date
    field :due_date, :date
    field :service_period_start, :date
    field :service_period_end, :date
    field :subtotal_cents, :integer, default: 0
    field :discount_cents, :integer, default: 0
    field :total_cents, :integer, default: 0
    field :currency, :string, default: "EUR"
    field :notes, :string
    field :voided_at, :utc_datetime_usec
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(invoice \\ %__MODULE__{}, params) do
    invoice
    |> cast(params, [
      :membership_id,
      :user_id,
      :membership_package_subscription_id,
      :invoice_number,
      :invoice_type,
      :status,
      :issue_date,
      :due_date,
      :service_period_start,
      :service_period_end,
      :subtotal_cents,
      :discount_cents,
      :total_cents,
      :currency,
      :notes,
      :voided_at,
      :params
    ])
    |> validate_required([
      :membership_id,
      :user_id,
      :invoice_number,
      :invoice_type,
      :status,
      :subtotal_cents,
      :discount_cents,
      :total_cents,
      :currency
    ])
    |> validate_inclusion(:invoice_type, ["manual", "renewal", "adjustment"])
    |> validate_inclusion(:status, [
      "draft",
      "issued",
      "partially_paid",
      "paid",
      "overdue",
      "void"
    ])
    |> validate_number(:subtotal_cents, greater_than_or_equal_to: 0)
    |> validate_number(:discount_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> validate_discount_not_above_subtotal()
    |> unique_constraint(:invoice_number)
    |> unique_constraint(:service_period_start,
      name: :finance_renewal_invoices_period_unique_index
    )
    |> foreign_key_constraint(:membership_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
  end

  defp validate_discount_not_above_subtotal(changeset) do
    subtotal_cents = get_field(changeset, :subtotal_cents)
    discount_cents = get_field(changeset, :discount_cents)

    if is_integer(subtotal_cents) and is_integer(discount_cents) and
         discount_cents > subtotal_cents do
      add_error(changeset, :discount_cents, "cannot exceed invoice subtotal")
    else
      changeset
    end
  end
end
