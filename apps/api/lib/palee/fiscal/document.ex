defmodule Palee.Fiscal.Document do
  @moduledoc "An issued fiscal document (ADR-241). Insert-only: the database refuses changes."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields ~w(id kind series sequence number issue_date issued_at currency prices_include_tax
             country_code language seller buyer payment_method net_cents tax_cents gross_cents
             tax_breakdown corrects_document_id source_type source_id idempotency_key
             request_hash content_hash journal_position created_by_id)a

  schema "fiscal_documents" do
    field :organization_id, :binary_id, read_after_writes: true
    field :kind, :string
    field :series, :string
    field :sequence, :integer
    field :number, :string
    field :issue_date, :date
    field :issued_at, :utc_datetime_usec
    field :currency, :string
    field :prices_include_tax, :boolean
    field :country_code, :string
    field :language, :string
    field :seller, :map
    field :buyer, :map
    field :payment_method, :string
    field :net_cents, :integer
    field :tax_cents, :integer
    field :gross_cents, :integer
    field :tax_breakdown, {:array, :map}, default: []
    field :corrects_document_id, :binary_id
    field :source_type, :string
    field :source_id, :binary_id
    field :idempotency_key, :string
    field :request_hash, :string
    field :content_hash, :string
    field :journal_position, :integer
    field :created_by_id, :binary_id

    has_many :lines, Palee.Fiscal.DocumentLine, foreign_key: :document_id

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def insert_changeset(attrs) do
    %__MODULE__{}
    |> cast(attrs, @fields)
    |> validate_required(
      ~w(kind series sequence number issue_date issued_at currency country_code language seller
         net_cents tax_cents gross_cents content_hash journal_position)a
    )
    |> unique_constraint([:organization_id, :series, :sequence])
    |> unique_constraint([:organization_id, :number])
    |> unique_constraint(:idempotency_key, name: :fiscal_documents_idempotency_index)
    |> check_constraint(:gross_cents, name: :fiscal_documents_amounts_check)
  end
end
