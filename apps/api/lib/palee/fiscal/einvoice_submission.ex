defmodule Palee.Fiscal.EInvoiceSubmission do
  @moduledoc "The outbox row sending one fiscal document over Peppol (ADR-250)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(document_id network status attempts polls next_attempt_at claimed_at environment
             idempotency_guid recipient_scheme recipient_identifier provider_submission_id
             submitted_at delivered_at last_error_code last_error_message)a

  schema "fiscal_einvoice_submissions" do
    field :organization_id, :binary_id, read_after_writes: true
    field :document_id, :binary_id
    field :network, :string
    field :status, :string, default: "pending"
    field :attempts, :integer, default: 0
    field :polls, :integer, default: 0
    field :next_attempt_at, :utc_datetime_usec
    field :claimed_at, :utc_datetime_usec
    field :environment, :string
    field :idempotency_guid, :binary_id
    field :recipient_scheme, :string
    field :recipient_identifier, :string
    field :provider_submission_id, :string
    field :submitted_at, :utc_datetime_usec
    field :delivered_at, :utc_datetime_usec
    field :last_error_code, :string
    field :last_error_message, :string

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(submission, attrs) do
    submission
    |> cast(attrs, @fields)
    |> validate_required(
      ~w(document_id network status idempotency_guid recipient_scheme recipient_identifier)a
    )
    |> unique_constraint([:document_id, :network])
    |> check_constraint(:status, name: :fiscal_einvoice_submissions_check)
  end
end
