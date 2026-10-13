defmodule MilosTraining.Finance.FinanceCorporateInvoice do
  @moduledoc "A per-period invoice to a corporate client for its seats (ADR-098)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "finance_corporate_invoices" do
    field :organization_id, :binary_id, read_after_writes: true
    field :corporate_client_id, :binary_id
    field :period_start, :date
    field :period_end, :date
    field :seat_billing, :string
    field :seats_billed, :integer
    field :unit_price_cents, :integer
    field :total_cents, :integer
    field :status, :string, default: "issued"
    field :issued_on, :date
    field :paid_on, :date
    field :invoice_number, :string
    field :due_on, :date
    field :last_reminded_on, :date
    field :reminder_count, :integer, default: 0

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(params) do
    %__MODULE__{}
    |> cast(params, [
      :corporate_client_id,
      :period_start,
      :period_end,
      :seat_billing,
      :seats_billed,
      :unit_price_cents,
      :total_cents,
      :issued_on,
      :invoice_number,
      :due_on
    ])
    |> validate_required([
      :corporate_client_id,
      :period_start,
      :period_end,
      :seat_billing,
      :seats_billed,
      :unit_price_cents,
      :total_cents,
      :issued_on,
      :due_on
    ])
    |> unique_constraint([:corporate_client_id, :period_start],
      name: :finance_corporate_invoices_period_index,
      message: "has already been invoiced for this period"
    )
  end

  def status_changeset(invoice, status, paid_on),
    do: change(invoice, status: status, paid_on: paid_on)

  def reminded_changeset(invoice, on),
    do: change(invoice, last_reminded_on: on, reminder_count: invoice.reminder_count + 1)
end
