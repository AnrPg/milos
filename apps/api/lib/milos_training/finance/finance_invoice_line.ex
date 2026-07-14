defmodule MilosTraining.Finance.FinanceInvoiceLine do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_invoice_lines" do
    field :finance_invoice_id, :binary_id
    field :membership_package_subscription_id, :binary_id
    field :line_type, :string, default: "membership_package"
    field :description, :string
    field :quantity, :integer, default: 1
    field :unit_amount_cents, :integer, default: 0
    field :discount_cents, :integer, default: 0
    field :total_cents, :integer, default: 0
    field :package_code_snapshot, :string
    field :package_family_snapshot, :string
    field :params, :map, default: %{}

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(line \\ %__MODULE__{}, params) do
    line
    |> cast(params, [
      :finance_invoice_id,
      :membership_package_subscription_id,
      :line_type,
      :description,
      :quantity,
      :unit_amount_cents,
      :discount_cents,
      :total_cents,
      :package_code_snapshot,
      :package_family_snapshot,
      :params
    ])
    |> validate_required([
      :finance_invoice_id,
      :line_type,
      :description,
      :quantity,
      :unit_amount_cents,
      :discount_cents,
      :total_cents
    ])
    |> validate_inclusion(:line_type, [
      "membership_package",
      "manual_charge",
      "discount",
      "adjustment"
    ])
    |> validate_number(:quantity, greater_than: 0)
    |> validate_number(:unit_amount_cents, greater_than_or_equal_to: 0)
    |> validate_number(:discount_cents, greater_than_or_equal_to: 0)
    |> validate_number(:total_cents, greater_than_or_equal_to: 0)
    |> validate_discount_not_above_subtotal()
    |> foreign_key_constraint(:finance_invoice_id)
    |> foreign_key_constraint(:membership_package_subscription_id)
  end

  defp validate_discount_not_above_subtotal(changeset) do
    quantity = get_field(changeset, :quantity)
    unit_amount_cents = get_field(changeset, :unit_amount_cents)
    discount_cents = get_field(changeset, :discount_cents)

    if is_integer(quantity) and is_integer(unit_amount_cents) and is_integer(discount_cents) and
         discount_cents > quantity * unit_amount_cents do
      add_error(changeset, :discount_cents, "cannot exceed line subtotal")
    else
      changeset
    end
  end
end
