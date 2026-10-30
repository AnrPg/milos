defmodule Palee.Fiscal.TillSignature do
  @moduledoc """
  The outbox row and signature data of one receipt (or special RKSV
  receipt) signed by the till device (ADR-251). The document stays
  immutable; its signature is printed from here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(document_id device kind period status attempts next_attempt_at claimed_at environment
             external_id transaction_number signature_counter signature_value
             signature_algorithm time_format started_at_device finished_at_device unit_serial
             register_serial receipt_number qr_code_data signed_at failed_at last_error_code
             last_error_message)a

  schema "fiscal_till_signatures" do
    field :organization_id, :binary_id, read_after_writes: true
    field :document_id, :binary_id
    field :device, :string
    field :kind, :string, default: "receipt"
    field :period, :date
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :environment, :string
    field :external_id, :binary_id
    field :transaction_number, :integer
    field :signature_counter, :integer
    field :signature_value, :string
    field :signature_algorithm, :string
    field :time_format, :string
    field :started_at_device, :utc_datetime_usec
    field :finished_at_device, :utc_datetime_usec
    field :unit_serial, :string
    field :register_serial, :string
    field :receipt_number, :string
    field :qr_code_data, :string
    field :signed_at, :utc_datetime_usec
    field :failed_at, :utc_datetime_usec
    field :last_error_code, :string
    field :last_error_message, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(signature, attrs) do
    signature
    |> cast(attrs, @fields)
    |> validate_required([:device, :kind, :status, :external_id])
    |> unique_constraint([:document_id, :device], name: :fiscal_till_signatures_document_index)
    |> unique_constraint([:organization_id, :device, :kind, :period],
      name: :fiscal_till_signatures_special_index
    )
    |> check_constraint(:status, name: :fiscal_till_signatures_check)
  end
end
