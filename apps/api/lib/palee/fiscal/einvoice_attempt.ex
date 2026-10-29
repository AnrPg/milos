defmodule Palee.Fiscal.EInvoiceAttempt do
  @moduledoc "One call to the access point with what went over the wire (ADR-250). Insert-only."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  @fields ~w(submission_id attempt operation environment outcome request_body response_status
             response_body error duration_ms started_at)a

  schema "fiscal_einvoice_attempts" do
    field :organization_id, :binary_id, read_after_writes: true
    field :submission_id, :binary_id
    field :attempt, :integer
    field :operation, :string
    field :environment, :string
    field :outcome, :string
    field :request_body, :string
    field :response_status, :integer
    field :response_body, :string
    field :error, :string
    field :duration_ms, :integer
    field :started_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(~w(submission_id attempt operation environment outcome started_at)a)
  end
end
