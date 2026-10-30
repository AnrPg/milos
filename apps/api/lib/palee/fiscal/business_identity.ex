defmodule Palee.Fiscal.BusinessIdentity do
  @moduledoc "A business's legal identity (ADR-240). Validated by `Domain.BusinessIdentityPolicy`."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @fields ~w(legal_name trade_name country_code tax_id vat_number tax_office registration_number
             activity_code vat_scheme street building_number postal_code city region email phone
             document_language currency branch_code fiscal_year_start_month iban qr_iban
             updated_by_id)a

  schema "fiscal_business_identities" do
    field :organization_id, :binary_id, read_after_writes: true
    field :legal_name, :string
    field :trade_name, :string
    field :country_code, :string
    field :tax_id, :string
    field :vat_number, :string
    field :tax_office, :string
    field :registration_number, :string
    field :activity_code, :string
    field :vat_scheme, :string, default: "standard"
    field :street, :string
    field :building_number, :string
    field :postal_code, :string
    field :city, :string
    field :region, :string
    field :email, :string
    field :phone, :string
    field :document_language, :string
    field :currency, :string
    field :branch_code, :integer, default: 0
    field :fiscal_year_start_month, :integer, default: 1
    # ADR-245: bank details printed on invoices and used by the Swiss QR-bill.
    field :iban, :string
    field :qr_iban, :string
    field :updated_by_id, :binary_id

    timestamps(type: :utc_datetime_usec)
  end

  def fields, do: @fields

  def changeset(identity \\ %__MODULE__{}, attrs) do
    identity
    |> cast(attrs, @fields, empty_values: [])
    |> validate_required([:country_code, :currency, :vat_scheme])
    |> unique_constraint(:organization_id)
    |> check_constraint(:vat_scheme, name: :fiscal_business_identities_scheme_check)
  end
end
